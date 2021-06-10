defmodule WasmcloudHostWeb.ProviderController do
  use WasmcloudHostWeb, :controller
  require HostCore

  # provider_file, provider_key, provider_contract_id, provider_link_name
  def start_provider(conn, params) do
    path = params["provider_file"].filename
    key = params["provider_key"]
    contract_id = params["provider_contract_id"]
    link_name = params["provider_link_name"]

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        path,
        key,
        link_name,
        contract_id
      )

    conn |> redirect(to: "/")
  end
end
