defmodule HostCore.WasmCloud.Native do
    use Rustler, otp_app: :host_core, crate: :hostcore_wasmcloud_native

    def extract_claims(_bytes), do: error()
    def generate_key(_keytype), do: error()

    # When the NIF is loaded, it will override functions in this module.
    # Calling error is handles the case when the nif could not be loaded.
    defp error, do: :erlang.nif_error(:nif_not_loaded)
end