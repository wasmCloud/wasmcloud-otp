defmodule HostCore.Claims.Server do
  require Logger
  use Gnat.Server

  # Topic wasmbus.rpc.{prefix}.claims.put, .get
  # claims fields: call_alias, issuer, name, revision, tags, version, public_key

  def request(%{topic: topic, body: body}) do
    cmd = topic |> String.split(".") |> Enum.at(4)
    Logger.info("Received claims command (#{cmd})")
    # PUT
    if cmd == "get" do
      # {:reply, claims}
    else
      refmap = Msgpax.unpack!(body) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      :ets.insert(:claims_table, {refmap.oci_url, refmap.public_key})
      :ok
    end
  end
end
