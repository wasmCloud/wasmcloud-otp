defmodule HostCore.Actors.ActorSupervisor do    
    use DynamicSupervisor

    def start_link(init_arg) do
      DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    end
  
    @impl true
    def init(_init_arg) do
      DynamicSupervisor.init(strategy: :one_for_one)
    end

    def start_actor(bytes) when is_binary(bytes) do               
        DynamicSupervisor.start_child(__MODULE__, {HostCore.Actors.ActorModule, bytes})
    end

end