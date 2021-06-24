defmodule WasmcloudHostWeb.ActorController do
  use WasmcloudHostWeb, :controller
  require HostCore

  def start_actor(conn, params) do
    replicas =
      if params["replicas"] do
        1..String.to_integer(params["replicas"])
      else
        1..1
      end

    cond do
      params["actor_file"] != nil ->
        {:ok, bytes} = File.read(params["actor_file"].path)

        replicas
        |> Enum.each(fn _ -> HostCore.Actors.ActorSupervisor.start_actor(bytes) end)

      params["actor_ociref"] != "" ->
        replicas
        |> Enum.each(fn _ ->
          HostCore.Actors.ActorSupervisor.start_actor_from_oci(params["actor_ociref"])
        end)

      true ->
        :error
    end

    conn |> redirect(to: "/")
  end

  def terminate_actor(conn, params) do
    public_key = params["public_key"]
    count = String.to_integer(params["count"])

    HostCore.Actors.ActorSupervisor.terminate_actor(public_key, count)
    # TODO: handle err
    conn
    |> Plug.Conn.send_resp(200, [])
    |> Plug.Conn.halt()
  end
end
