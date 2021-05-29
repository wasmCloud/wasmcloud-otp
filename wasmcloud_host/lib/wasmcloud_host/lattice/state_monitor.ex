defmodule WasmcloudHost.Lattice.StateMonitor do
    use GenServer, restart: :transient
    alias Phoenix.PubSub

    require Logger
   
    defmodule State do
        defstruct [:actors, :providers, :linkdefs, :refmaps, :claims]
    end

    def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: :state_monitor)
    end

    @impl true
    def init(opts) do
        state = %State{ actors: [], providers: [], linkdefs: %{}, refmaps: %{}, claims: %{}}
        prefix = HostCore.Host.lattice_prefix()
        
        topic = "wasmbus.ctl.#{prefix}.events"        
        {:ok, _sub} = Gnat.sub(:control_nats, self(), topic)

        ldtopic = "wasmbus.rpc.#{prefix}.*.*.linkdefs.*"
        {:ok, _sub} = Gnat.sub(:lattice_nats, self(), ldtopic)

        {:ok, state}
    end

    @impl true
    def handle_call(:actor_query, _from, state) do
        {:reply, state.actors, state}
    end

    @impl true
    def handle_call(:provider_query, _from, state) do
        {:reply, state.providers, state}
    end

    @impl true
    def handle_call(:linkdef_query, _from, state) do
        {:reply, state.linkdefs, state}
    end

    @impl true
    def handle_info({:msg, 
                        %{body: body,
                        topic: topic}
                    }, state) do
        Logger.info "StateMonitor handle info #{topic}"
        state = cond do
            String.ends_with?(topic, ".events") ->
                handle_event(state, body)
            String.contains?(topic, ".linkdefs.") ->
                handle_linkdef(state, body, topic)
        end  
        IO.inspect state      

        {:noreply, state}
    end
    
    def get_actors() do
        GenServer.call(:state_monitor, :actor_query)
    end

    def get_providers() do
        GenServer.call(:state_monitor, :provider_query)
    end

    def get_linkdefs() do
        GenServer.call(:state_monitor, :linkdef_query)
    end

    defp handle_linkdef(state, body, topic) do
        Logger.info "Handling linkdef state update"
        cmd = topic |> String.split(".") |> Enum.at(6)
        ld = Msgpax.unpack!(body)
        key = {ld["actor_id"], ld["contract_id"], ld["link_name"]}
        map = %{values: ld["values"], provider_key: ld["provider_id"]}

        linkdefs = if cmd == "put" do
            Map.put(state.linkdefs, key, map)
        else
            Map.delete(state.linkdefs, key)
        end        
        PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:linkdefs, linkdefs})
        %State{state | linkdefs: linkdefs }
    end


    defp handle_event(state, body) do
        evt = body
                |> Cloudevents.from_json!        
        process_event(state, evt)
    end        
    
    defp process_event(state, 
        %Cloudevents.Format.V_1_0.Event{
            data: %{
            "public_key" => pk
            },
            datacontenttype: "application/json",        
            type: "com.wasmcloud.lattice.actor_started"
        }
      ) do

        actors = [pk | state.actors ]
        PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:actors, actors})
        %State{state | actors: actors}
    end

    defp process_event(state, 
        %Cloudevents.Format.V_1_0.Event{
            data: %{
            "public_key" => pk
            },
            datacontenttype: "application/json",        
            type: "com.wasmcloud.lattice.provider_started"
        }
      ) do
        
        providers = [pk | state.providers ]
        PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:providers, providers})
        %State{state | providers: providers}
    end
    
end