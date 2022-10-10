## Opportunity for refactoring

(Optional)

As currently implemented, the code is okay, however, it is abit hard to read

### Possible refactor

```elixir
@doc """
Always remember the documentation.

Returns the spec for new Gnat.ConsumerSupervisor if the policy change is provided
"""
def spec do
    case System.get_env("WASMCLOUD_POLICY_CHANGES_TOPIC") do
        topic when not is_nil(topic) -> get_spec(topic)
        _ -> []
    end
end

defp get_spec(topic) do
    [Supervisor.child_spec({Gnat.ConsumerSupervisor, get_settings(topic), id: :policy_manager})]
end

defp get_settings(topic) do
    %{
        connection_name: :control_nats.
        module: __MODULE__,
        subscription_topics: [%{topic: topic}]
    }
end


```
