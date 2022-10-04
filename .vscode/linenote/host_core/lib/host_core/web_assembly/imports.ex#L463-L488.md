## opportunity for refactoring

1. The generation of this message could be moved to new function that just generates a new message payload

2. Within the new function, the if checks for keys can be moved to individual functions

```elixir
defp generate_msg(actor, target_key, target_type, namespace, operation, payload_bytes) do
    params = %{
        source: %{
            public_key: actor,
            contract_id: nil,
            link_name: nil
        },
        dest: %{
            public_key: target_key,
            link_name: link_name(target_type, namespace),
            contract_id: contract_id(target_type, namesapce)
        },
        operation: operation,
        bytes: payload_bytes
    }

    CloduEvent.new(params)
end

defp contract_id(target_type, namespace) do
    case target_type do
        :provider -> namespace,
        _ -> nil
    end
end

defp link_name(target_type, binding) do
    case target_type do
        :provider -> binding,
        _ -> nil
    end
end

```
