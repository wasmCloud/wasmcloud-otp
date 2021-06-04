defmodule HostCore.Providers do
    @moduledoc """
    Documentation for `HostCore.Providers`.
    """

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

end