defmodule WasmcloudHostWeb.ActorController do
  use WasmcloudHostWeb, :controller
  require HostCore

  def start_actor(conn, params) do
    IO.inspect(0..String.to_integer(params["replicas"]))

    if upload = params["actor_file"] do
      {:ok, bytes} = File.read(upload.path)

      if replicas = params["replicas"] do
        1..String.to_integer(replicas)
        |> Enum.each(fn _ -> HostCore.Actors.ActorSupervisor.start_actor(bytes) end)
      end
    end

    conn |> redirect(to: "/")
  end
end
