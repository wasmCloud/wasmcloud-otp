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
        IO.puts topic
        {:ok, _sub} = Gnat.sub(:control_nats, self(), topic)

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
    def handle_info({:msg, 
                    %{body: body}}, state) do                        
        evt = body
              |> Cloudevents.from_json!        
        state = process_event(state, evt)

        {:noreply, state}
    end
    
    def get_actors() do
        GenServer.call(:state_monitor, :actor_query)
    end

    def get_providers() do
        GenServer.call(:state_monitor, :provider_query)
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