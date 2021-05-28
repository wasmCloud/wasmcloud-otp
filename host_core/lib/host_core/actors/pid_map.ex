defmodule HostCore.Actors.PidMap do
    use GenServer, restart: :transient

    @doc """
    Starts the pidmap module. Do not start this manually, the supervision tree will
    take care of it.
    """
    def start_link(_init_arg) do
        GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    @impl true
    def init(state) do        
        {:ok, state}
    end

    @doc """
    Puts a PID into the pidmap. The key can be any string, but we generally assume that it will be one of:
    * A 56-character public key for a module (prefix "M")
    * A 56-character public key for a capability provider (prefix "V")
    * A free-form string that is the module's call alias
    * An OCI reference URL
    Note that any given PID can have at minimum one entry but up to 3 entries, if we have all aliases available to us. When
    We try and find an entity, we just look it up in the pidmap.
    """
    def put(key, value) do
        GenServer.call(__MODULE__, {:put, key, value})
    end

    @doc """
    Removes a key from the pid map. This may not remove all occurrences of the PID from the map if an entity has more than one alias
    """
    def remove(key) do 
        GenServer.call(__MODULE__, {:remove, key})
    end

    @doc """
    Looks up a PID by an alias or public key string
    """
    def find_pid(key) do
        GenServer.call(__MODULE__, {:find, key})
    end


    @impl true
    def handle_call({:put, key, value}, _from, state = %{}) do
        state = Map.put(state, key, value)
        Process.monitor(value)

        {:reply, state, state}
    end    

    @impl true
    def handle_call({:remove, key}, _from, state) do
        {:reply, Map.delete(state, key)}
    end

    @impl true
    def handle_call({:find, key}, _from, state) do
        {:reply, Map.get(state, key), state}
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, object, _reason}, state) do
        {:noreply, :maps.filter(fn _, v -> v != object end, state) }        
    end


    
end