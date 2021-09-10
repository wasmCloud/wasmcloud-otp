defmodule HostCore.Claims.Manager do
  @moduledoc false
  require Logger

  def lookup_claims(public_key) do
    case :ets.lookup(:claims_table, public_key) do
      [c] -> {:ok, c}
      [] -> :error
    end
  end

  def cache_claims(key, claims) do
    :ets.insert(:claims_table, {key, claims})
  end

  def cache_call_alias(call_alias, public_key) do
    if call_alias != nil && String.length(call_alias) > 1 do
      :ets.insert_new(:callalias_table, {call_alias, public_key})
    end
  end

  def put_claims(claims) do
    key = claims.public_key

    claims = %{
      call_alias:
        if claims.call_alias == nil do
          ""
        else
          claims.call_alias
        end,
      iss: claims.issuer,
      name:
        if claims.name == nil do
          ""
        else
          claims.name
        end,
      caps:
        if claims.caps == nil do
          ""
        else
          Enum.join(claims.caps, ",")
        end,
      rev:
        if claims.revision == nil do
          "0"
        else
          Integer.to_string(claims.revision)
        end,
      tags:
        if claims.tags == nil do
          ""
        else
          Enum.join(claims.tags, ",")
        end,
      version: claims.version,
      sub: claims.public_key
    }

    cache_call_alias(claims.call_alias, claims.sub)
    cache_claims(key, claims)
    publish_claims(claims)
  end

  defp publish_claims(claims) do
    prefix = HostCore.Host.lattice_prefix()
    topic = "lc.#{prefix}.claims.#{claims.sub}"

    Gnat.pub(:control_nats, topic, Jason.encode!(claims))
  end

  def get_claims() do
    :ets.tab2list(:claims_table)
    |> Enum.map(fn {_pk, %{} = claims} -> claims end)
  end
end
