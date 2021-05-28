defmodule HostCore.Providers.ProviderSupervisor do
    use DynamicSupervisor

    def start_link(init_arg) do
      DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
    end
  
    @impl true
    def init(_init_arg) do    

      DynamicSupervisor.init(strategy: :one_for_one)

    end

    def start_executable_provider(path, public_key, link_name) do               
        DynamicSupervisor.start_child(__MODULE__, {HostCore.Providers.ProviderModule, {:executable, path, public_key, link_name}})
    end    
    
end