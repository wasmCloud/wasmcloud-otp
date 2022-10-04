## Recommendation for future

- As an opinion, the check for whether the process is alive should be done at the client's side so that this module is only concerned with making the `GenServer.call`

Examples

```elixir
defmodule Module.Client do
    @moduledoc false
    alias HostCore.Actors.ActorModule

    def some_function(pid) do
        # gets pid from somewhere
        if Process.alive?(pid), do: ActorModule.claims(pid), else: "n/a"
    end
end

defmodule HostCore.Actors.ActorModule do
    @moduledoc false
    use GenServer

    @doc false
    def claims(pid) do
        GenServer.call(pid, :get_claims)
    end
end

```
