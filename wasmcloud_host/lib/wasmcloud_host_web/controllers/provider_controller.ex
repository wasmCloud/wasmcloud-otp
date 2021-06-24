defmodule WasmcloudHostWeb.ProviderController do
  use WasmcloudHostWeb, :controller
  require HostCore

  def start_provider(conn, params) do
    upload = params["provider_file"]
    ociref = params["provider_ociref"]
    key = params["provider_key"]
    contract_id = params["provider_contract_id"]
    link_name = params["provider_link_name"]

    # TODO: Handle errors with UI messages

    cond do
      upload != nil ->
        # Temporary logic to write provider to temp dir.
        # This should be removed in favor of loading a provider archive instead of a binary
        {:ok, bytes} = File.read(upload.path)
        dir = System.tmp_dir!()
        tmp_file = Path.join(dir, upload.filename)
        File.write!(tmp_file, bytes)
        File.chmod(tmp_file, 0o755)

        case HostCore.Providers.ProviderSupervisor.start_executable_provider(
               tmp_file,
               key,
               link_name,
               contract_id
             ) do
          {:ok, _pid} -> :ok
          {:error, _reason} -> :error
        end

      ociref != nil && ociref != "" ->
        case HostCore.Providers.ProviderSupervisor.start_executable_provider_from_oci(
               ociref,
               link_name
             ) do
          {:ok, _pid} -> :ok
          {:error, _reason} -> :error
          {:stop, _reason} -> :error
        end

      true ->
        :error
    end

    conn |> redirect(to: "/")
  end
end
