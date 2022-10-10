# Opportunity for refactoring

As it is currently implemented, there is no problem and it will work.

However, there are a few notable readability issues that are present:

1. Using a function call as the first argument to a pipe.

   - Instead of doing this, always prefer using a raw value as the first argument to a pipe.
   - Enforce this code style using `credo`

2. Piping to a single function.

   - Instead, prefer to avoid using pipes when just calling a single function.

3. Not making use of the `alias` functionality

   - Throughout this module, there's a call to `HostCore.Actors.ModuleName`

   - To make the code more readable, consider the use of `alias`

4. (Optional) When naming functions that do not accept any argument, do not include the parenthesis

   - This is also optional. but the community guidelines prefer without the parenthesis.

   - Include the Credo check [Credo.Check.Readability.ParenthesesOnZeroArityDef](https://hexdocs.pm/credo/Credo.Check.Readability.ParenthesesOnZeroArityDefs.html)

   - When using the credo check above, chose whether or not to include the parenthesis. The important thing is to ensure that depending on your choice, you ensure it's consistent throughout the code base.

5. (Optional) Whenver possible prefer the using `for` instead of Enum.

   - This is a matter of preference, and there's nothing against the current implementation using Enum.

## Possible refactor

```elixir
defmodule HostCore.ControlInterface.ACL do
    @moduledoc false

    alias HostCore.Actors.{ActorModule, ActorSupervisor}


    def all_actors do
        for {id, pids} <- ActorSupervisor.all_actors() do
            name = get_name(id)
            revision = get_revision(id)
            image_ref = image_ref(pids)
            instances = get_instances(pids, revision)

            %{
                id: id,
                name: name,
                instances: instances,
                image_ref: image_ref
            }
        end
    end

    defp image_ref(pids) do
        pids
        |> Enum.at(0)
        |> ActoModule.ociref()
    end

    defp get_instances(pids, revision) do
        for pid <- pids do
            %{
                revision: revision,
                instance_id: ActorModule.instance_id(pid),
                annotations: ActorModule.annotations(pid)
            }
        end
    end

end

```
