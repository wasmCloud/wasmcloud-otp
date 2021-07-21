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
      claims = get_claims()
      {:reply, Msgpax.pack!(claims)}
    else
      claims = Msgpax.unpack!(body) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      # Note the name difference here, outside of OTP the claims use JWT naming conventions
      key = claims.sub
      HostCore.Claims.Manager.cache_claims(key, claims)
      # Only stores call alias if it hasn't previously been claimed
      HostCore.Claims.Manager.cache_call_alias(claims.call_alias, claims.sub)

      :ok
    end
  end

  def get_claims() do
    :ets.tab2list(:claims_table)
    |> Enum.map(fn {_pk, %{} = claims} -> claims end)
  end
end
