defmodule HostCore.Refmaps.Server do
  require Logger
  use Gnat.Server

  # Topic wasmbus.rpc.{prefix}.refmaps.put
  # Refmap fields: oci_url, public_key
  def request(%{topic: topic, body: body}) do
    cmd = topic |> String.split(".") |> Enum.at(4)
    Logger.info("Received refmaps command (#{cmd})")

    case cmd do
      "put" ->
        refmap = Msgpax.unpack!(body) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
        HostCore.Refmaps.Manager.cache_refmap(refmap.oci_url, refmap.public_key)
        :ok

      "get" ->
        refmaps = get_refmaps()
        {:reply, Msgpax.pack!(refmaps)}
    end
  end

  def get_refmaps() do
    :ets.tab2list(:refmap_table)
    |> Enum.map(fn {oci_url, public_key} -> %{oci_url: oci_url, public_key: public_key} end)
  end
end
