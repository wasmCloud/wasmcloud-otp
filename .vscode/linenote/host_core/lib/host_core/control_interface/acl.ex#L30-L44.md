## Opportunity for refactoring

The same actions can be taken in this functions as the review comments left for the function `all_actors/0`

### Possible refactoring

```elixir
def all_providers do
    # this function assumes that you have aliased the HostCore.Provides module
    # at the beginning of the module definition
    for {pid, pk, link, _, instance_id} <- ProviderSupervisor.all_providers() do
        name = get_name(pk)
        revision = get_revision(pk)
        image_ref = ProviderModule.ociref(pid)
        annotations = ProviderModule.annotations(pid)

        %{
            id: pk,
            name: name,
            link_name: link,
            revision: revision,
            image_ref: image_ref,
            instance_id: instance_id,
            annotations: annotations
        }

    end

end

```
