defmodule HostCore.Actors.ActorModule do    
    use GenServer, restart: :transient
    
    require Logger
    alias HostCore.WebAssembly.Imports    
    alias HostCore.Actors.PidMap

    defmodule State do
        defstruct [:guest_request, 
                   :guest_response,
                   :host_response,
                   :guest_error,
                   :host_error,
                   :instance,
                   :api_version,
                   :invocation,
                   :claims
                ]
    end

    defmodule Invocation do
        defstruct [:operation, :payload]
    end

    @doc """
    Starts the Actor module
    """
    def start_link(bytes) do
        GenServer.start_link(__MODULE__, bytes)
    end

    def perform_operation(pid, operation, payload) do
        GenServer.call(pid, {:invoke, {operation, payload}})
    end

    def current_invocation(pid) do
        GenServer.call(pid, :get_invocation)
    end

    def api_version(pid) do
        GenServer.call(pid, :get_api_ver)
    end

    def claims(pid) do 
        GenServer.call(pid, :get_claims)
    end

    @impl true
    def init(bytes) do        
        case HostCore.WasmCloud.Native.extract_claims(bytes) do
            {:error, err} -> Logger.error("Failed to extract claims from WebAssembly module"); {:stop, err}  
            claims -> start_actor(claims, bytes)
        end        
    end    

    # Invoke __guest_call with the incoming binary payload and return a binary payload (or error)
    @impl true    
    def handle_call({:invoke, {operation, payload}}, _from, agent) do
        Logger.info("Handling call")
        perform_invocation(agent, operation, payload)        
    end

    def handle_call(:get_api_ver, _from, agent) do
        {:reply, Agent.get(agent, fn content -> content.api_version end), agent}
    end

    def handle_call(:get_claims, _from, agent) do
        {:reply, Agent.get(agent, fn content -> content.claims end), agent}
    end

    @impl true
    def handle_call(:get_invocation, _from, agent) do
        Logger.info("Getting invocation")
        {:reply, Agent.get(agent, fn content -> content.invocation end), agent}
    end

    @impl true
    def handle_info({:msg,
        %{
            body: body,            
            reply_to: reply_to,            
            topic: topic,            
        }
    }, agent) do
        Logger.info("Received invocation on #{topic}")
        {:ok, inv} = Msgpax.unpack(body) # TODO - handle failure
        IO.inspect(inv)
        # TODO error handle
        # TODO refactor perform invocation so it's not required to run from inside handle_call
        {:reply, {:ok, response}, _state} =
            perform_invocation(agent, inv["operation"],
                :binary.list_to_bin(inv["msg"])) 
        
        ir = %{
            msg: :binary.bin_to_list(response),
            invocation_id: inv["id"],            
        }
        IO.inspect(ir)        

        Gnat.pub(:lattice_nats, reply_to, 
                 ir |> Msgpax.pack!())
        {:noreply, agent}
    end


    defp start_actor(claims, bytes) do
        IO.inspect claims 

        HostCore.ClaimsManager.put_claims(claims)
        
        {:ok, agent} = Agent.start_link fn -> %State{claims: claims} end
        PidMap.put(claims.public_key, self()) # Register this process with the public key
        if claims.call_alias != nil do
            PidMap.put(claims.call_alias, self())
        end

        prefix = HostCore.Host.lattice_prefix()
        {:ok, _subscription} = Gnat.sub(:lattice_nats, self(), 
            "wasmbus.rpc.#{prefix}.#{claims.public_key}")

        imports = %{    
            wapc: Imports.wapc_imports(agent),
            frodobuf: Imports.frodobuf_imports(agent)
        }        
        Wasmex.start_link(%{bytes: bytes, imports: imports})
            |> prepare_module(agent)
    end

    defp perform_invocation(agent, operation, payload) do
        IO.inspect payload
        Logger.info "performing invocation #{operation}"
        raw_state = Agent.get(agent, fn content -> content end)        
        raw_state = %State{raw_state | guest_response: nil,
                        guest_request: nil,
                        guest_error: nil,
                        host_response: nil,
                        host_error: nil,
                        invocation: %Invocation{operation: operation, payload: payload}
        }
        Agent.update(agent, fn _content -> raw_state end)
        Logger.info("Agent state updated")
        
        
        # invoke __guest_call
        # if it fails, set guest_error, return 1
        # if it succeeeds, set guest_response, return 0
        Wasmex.call_function(raw_state.instance, :__guest_call, [byte_size(operation), byte_size(payload)])
        |> to_guest_call_result(agent)
    end

    defp to_guest_call_result({:ok, [res]}, agent) do
        Logger.info("OK result")
        state = Agent.get(agent, fn content -> content end)
        case res do 
            1 -> {:reply, {:ok, state.guest_response}, agent}
            0 -> {:reply, {:error, state.guest_error}, agent}
        end
    end

    defp to_guest_call_result({:error, err}, agent) do  
        {:reply, {:error, err}, agent}
    end    

    defp prepare_module({:ok, instance }, agent) do

        api_version = case Wasmex.call_function(instance, :__frodobuf_api_version, []) do
            {:ok, [v]} -> v
            _ -> 0
        end
        claims = Agent.get(agent, fn content -> content.claims end)
        Wasmex.call_function(instance, :start, [])
        Wasmex.call_function(instance, :wapc_init, [])
        Agent.update(agent, fn content -> %State{ content | api_version: api_version, instance: instance} end)

        publish_actor_started(claims.public_key)
        {:ok, agent}        
    end

    def publish_actor_started(actor_pk) do
        prefix = HostCore.Host.lattice_prefix()
        stamp = DateTime.utc_now() |> DateTime.to_iso8601        
        host = HostCore.Host.host_key()        
        msg = %{
            specversion: "1.0",
            time: stamp,
            type: "com.wasmcloud.lattice.actor_started",
            source: "#{host}",
            datacontenttype: "application/json",
            id: UUID.uuid4(),
            data: %{
                public_key: actor_pk
            }
        } 
        |> Cloudevents.from_map!()
        |> Cloudevents.to_json()
        topic = "wasmbus.ctl.#{prefix}.events"

        Gnat.pub(:control_nats, topic, msg)
    end
end