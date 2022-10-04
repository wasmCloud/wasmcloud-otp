## Opportunity for refactoring

Nesting of `case`, or `if` is okay, however, it does make it hard for readability and maintainability.

One of the things we can do, is to ensure that the `case` and/or `if` has one level of abstraction.

One level of abstraction is explained better exaplained by Robert Cecil Martin in the book `Clean Code`

## Recommedation

This piece of code can be refactored to:

```elixir
defp identify_target(token) do
    case get_target(opts) do
        :unknown ->
            {:error, :alias_not_found, token}

        target ->
            {:ok, %{token | target: target}}
    end
end

defp get_target(%{namespace: namespace, binding: binding, prefix: prefix, source_actor: actor_id}) do
    case HostCore.Linkdefs.Manager.lookup_link_definition(actor_id, namesapce, binding) do
        {:ok, ld} ->
            Tracer.set_attribute("target_provider", ld.provider_id)
            {:provider, ld.provider_id, "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{binding}"}

        _ ->
            check_namespace(namespace)
    end
end


defp check_namespace(namespace) do
    if String.starts_with?(namespace, "M") && String.length(namespace) == 56 do
        Tracer.set_attribute("target_actor", namespace)
        {:actor, namespace, "wasmbus.rpc.#{prefix}.#{namespace}"}
    else
        do_lookup_call_alias(namespace)
    end
end

defp do_lookup_call_alias(namespace) do
    case lookup_call_alias(namespace) do
        {:ok, actor_key} ->
            Tracer.set_attribute("target_actor", actor_key)
            {:actor, actor_key, "wasmbus.rpc.#{prefix}.#{actor_key}"}

        :error ->
            :unknown
    end
end

```
