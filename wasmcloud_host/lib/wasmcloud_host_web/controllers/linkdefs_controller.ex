defmodule WasmcloudHostWeb.LinkdefsController do
  use WasmcloudHostWeb, :controller
  require HostCore

  def define_link(conn, params) do
    actor = params["actor_id"]
    contract_id = params["contract_id"]
    link_name = params["link_name"]
    provider_key = params["provider_id"]
    # will likely have to reformat this
    # values = params["values"]
    # provider_key = "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
    values = %{PORT: "8080"}

    HostCore.LinkdefsManager.put_link_definition(
      actor,
      contract_id,
      link_name,
      provider_key,
      values
    )

    conn |> redirect(to: "/")
  end
end
