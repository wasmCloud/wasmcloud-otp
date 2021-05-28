defmodule HostCore.Providers do        

    @doc """
    Retrieves a provider's public key from the cache using a tuple of the namespace
    and link name as a key. For example, to get the public key of the provider currently
    known to support `wasmcloud:httpserver`/`default`, you would pass in "wasmcloud:httpserver"
    and "default"
    """
    def lookup_provider(namespace, link_name) do
        case :ets.lookup(:provider_registry, {namespace, link_name}) do
            [pk] -> {:ok, pk}
            [] -> :error
        end
    end

    def lookup_link_definition(actor, contract_id, link_name) do
        case :ets.lookup(:linkdef_registry, {actor, contract_id, link_name}) do
            [ld] -> {:ok, ld}
            [] -> :error
        end
    end

    def put_link_definition(actor, contract_id, link_name, provider_key, values) do
        key = {actor, contract_id, link_name}
        map = %{values: values, provider_key: provider_key}

        :ets.insert(:linkdef_registry, {key, map})
    end

end