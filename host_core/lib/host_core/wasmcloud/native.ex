defmodule HostCore.WasmCloud.Native do
  @moduledoc false
  use Rustler, otp_app: :host_core, crate: :hostcore_wasmcloud_native

  def extract_claims(_bytes), do: error()
  def generate_key(_keytype), do: error()

  def pk_from_seed(_seed), do: error()
  def validate_antiforgery(_bytes, _valid_issuers), do: error()

  def generate_invocation_bytes(
        _host_seed,
        _origin,
        _target_type,
        _target_key,
        _target_contract_id,
        _target_link_name,
        _op,
        _msg
      ),
      do: error()

  def get_oci_bytes(_oci_ref, _allow_latest, _allowed_insecure), do: error()
  def par_from_bytes(_bytes), do: error()
  def par_cache_path(_subject, _rev, _contract_id, _link_name), do: error()
  def detect_core_host_labels(), do: error()
  def get_actor_bindle(_bindle_id), do: error()
  def get_provider_bindle(_bindle_id), do: error()

  # When the NIF is loaded, it will override functions in this module.
  # Calling error is handles the case when the nif could not be loaded.
  defp error, do: :erlang.nif_error(:nif_not_loaded)

  defmodule ProviderArchive do
    @moduledoc false
    def from_bytes(bytes), do: HostCore.WasmCloud.Native.par_from_bytes(bytes)
  end
end
