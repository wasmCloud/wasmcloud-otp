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
end
