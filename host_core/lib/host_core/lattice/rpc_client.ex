defmodule HostCore.Lattice.RpcClient do
    use Rustler, otp_app: :host_core, crate: :lattice_rpc

    @doc """
    A wrapper around the low-level lattice RPC protocol. Sends the binary payload and receives
    back an opaque binary payload suitable for storage in either the host_response or host_error
    fields of the module state, depending on success or fail. Also returns a numeric code indicating
    a boolean value of success (0 - no, 1 - yes).
    """
    def perform_invocation(actor, binding, namespace, operation, payload, claims, seed, prefix, provider_key), do: error()
    
    # When the NIF is loaded, it will override functions in this module.
    # Calling error handles the case when the nif could not be loaded.
    defp error, do: :erlang.nif_error(:nif_not_loaded)
    
end