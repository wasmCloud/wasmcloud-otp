defmodule WasmcloudHostWeb.ProviderController do
  use WasmcloudHostWeb, :controller
  require HostCore

  def start_provider(conn, params) do
    upload = params["provider_file"]
    key = params["provider_key"]
    contract_id = params["provider_contract_id"]
    link_name = params["provider_link_name"]

    # Temporary logic to write provider to temp dir.
    # This should be removed in favor of loading a provider archive instead of a binary

    {:ok, bytes} = File.read(upload.path)
    dir = System.tmp_dir!()
    tmp_file = Path.join(dir, upload.filename)
    File.write!(tmp_file, bytes)
    File.chmod(tmp_file, 0o755)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        tmp_file,
        key,
        link_name,
        contract_id
      )

    conn |> redirect(to: "/")
  end
end
