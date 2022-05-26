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

  def set_chunking_connection_config(_config), do: error()
  def dechunk_inv(_inv_id), do: error()
  def chunk_inv(_inv_id, _bytes), do: error()

  def get_oci_bytes(_creds, _oci_ref, _allow_latest, _allowed_insecure), do: error()
  def get_oci_path(_creds, _path, _allow_latest, _allowed_insecure), do: error()
  def par_from_path(_path, _link_name), do: error()
  def par_cache_path(_subject, _rev, _contract_id, _link_name), do: error()
  def detect_core_host_labels(), do: error()
  def get_actor_bindle(_creds, _bindle_id), do: error()
  def get_provider_bindle(_creds, _bindle_id, _link_name), do: error()

  # When the NIF is loaded, it will override functions in this module.
  # Calling error is handles the case when the nif could not be loaded.
  defp error, do: :erlang.nif_error(:nif_not_loaded)

  defmodule ProviderArchive do
    @moduledoc false
    def from_path(path, link_name), do: HostCore.WasmCloud.Native.par_from_path(path, link_name)
  end
end
