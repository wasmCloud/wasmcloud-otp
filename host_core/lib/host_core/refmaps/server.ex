defmodule HostCore.Refmaps.Server do
  require Logger
  use Gnat.Server

  # Topic wasmbus.rpc.{prefix}.refmaps.put
  # Refmap fields: oci_url, public_key
  def request(%{topic: topic, body: body}) do
    cmd = topic |> String.split(".") |> Enum.at(4)
    Logger.info("Received refmaps command (#{cmd})")

    if cmd == "put" do
      refmap = Msgpax.unpack!(body) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      :ets.insert(:refmap_table, {refmap.oci_url, refmap.public_key})
    end

    :ok
  end
end
