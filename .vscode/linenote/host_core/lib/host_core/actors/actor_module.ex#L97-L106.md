## Observations:

The `init/1` callback is being used to start an actor, however, this is also been done within the callback.

While this is okay, doing this does come with some important effects, especially because the function `start_actor/4` seems to be doing a lot of work:

    1. Performing heavy initializations within the `init/1` callback delays the startup of the Supervision tree because is is done synchronously.

    2. For GenServers, the timeout for initialization is set to `5000 ms`, meaning that if the process is not initialized within this time, it will return an `{:error, :timeout}`

    This can be mitigated by passing the timeout to the `GenServer.start_link/4` function

### Recommendations:

1. Within the `init/1` callback, just initialize the Agent and then return `{:ok, agent, {:continue, :start_actor}}`

   ```elixir
   def init({_claims, _bytes, _oci, _annotations} = opts) do
   {:ok, agent} = Agent.start_link(fn -> new_state(opts) end)

   {:ok, agent, {:continue, {:start_actor, opts}}}
   end

   @impl GenServer
   def handle_continue({:start_actor, opts}, agent) do
       case start_actor(opts, agent) do
           {:ok, agent} -> {:noreply, agent}
           {:error, _e} -> {:stop, :normal, agent}
       end
   end

   defp new_state({claims, _bytes, _oci, annotations}) do
       %State{
           claims: claims,
           instance_id: UUID.uuid4(),
           healthy: false,
           annotations: annotations
       }
   end

   defp start_actor({claims, bytes, oci, annotations}, agent) do
       # Add code for starting the actor, minus the call to Agent.start_link/1
       # because it's already been started in the init

       # ...
   end

   ```
