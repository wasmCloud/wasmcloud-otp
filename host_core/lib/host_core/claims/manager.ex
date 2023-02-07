defmodule HostCore.Claims.Manager do
  @moduledoc false
  require Logger

  import HostCore.Jetstream.MetadataCacheLoader, only: [broadcast_event: 3]

  alias HostCore.Jetstream.Client, as: JetstreamClient
  alias HostCore.Vhost.VirtualHost

  @type cached_claimsdata :: %{
          call_alias: String.t(),
          iss: String.t(),
          name: String.t(),
          caps: String.t(),
          rev: String.t(),
          tags: String.t(),
          version: String.t(),
          sub: String.t(),
          contract_id: String.t() | nil
        }

  @spec lookup_claims(lattice_prefix :: String.t(), public_key :: String.t()) ::
          :error | {:ok, map()}
  def lookup_claims(lattice_prefix, public_key) do
    case :ets.lookup(claims_table_atom(lattice_prefix), public_key) do
      [{^public_key, %{} = claims}] -> {:ok, claims}
      [] -> :error
    end
  end

  @spec cache_claims(
          lattice_prefix :: String.t(),
          public_key :: String.t(),
          claims :: cached_claimsdata()
        ) :: any()
  def cache_claims(lattice_prefix, public_key, claims) do
    cache_call_alias(lattice_prefix, claims.call_alias, public_key)
    :ets.insert(claims_table_atom(lattice_prefix), {public_key, claims})
  end

  def uncache_claims(lattice_prefix, public_key) do
    :ets.delete(claims_table_atom(lattice_prefix), public_key)
  end

  def cache_call_alias(lattice_prefix, call_alias, public_key) do
    if call_alias != nil && String.length(call_alias) > 1 do
      :ets.insert_new(callalias_table_atom(lattice_prefix), {call_alias, public_key})
    end
  end

  def put_claims(host_id, lattice_prefix, claims) do
    public_key = claims.public_key

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
      sub: public_key,
      contract_id: Map.get(claims, :contract_id) || ""
    }

    cache_claims(lattice_prefix, public_key, claims)
    publish_claims(host_id, lattice_prefix, claims)
  end

  def claims_table_atom(lattice_prefix) do
    String.to_atom("claims_#{lattice_prefix}")
  end

  def callalias_table_atom(lattice_prefix) do
    String.to_atom("callalias_#{lattice_prefix}")
  end

  def lookup_call_alias(lattice_prefix, call_alias) do
    case :ets.lookup(callalias_table_atom(lattice_prefix), call_alias) do
      [{_call_alias, pkey}] ->
        {:ok, pkey}

      [] ->
        :error
    end
  end

  defp publish_claims(host_id, lattice_prefix, claims) do
    config = VirtualHost.config(host_id)

    JetstreamClient.kv_put(
      lattice_prefix,
      config.js_domain,
      "CLAIMS_#{claims.sub}",
      Jason.encode!(claims)
    )

    broadcast_event(:claims_added, claims, lattice_prefix)
  end

  def get_claims(lattice_prefix) when is_binary(lattice_prefix) do
    tbl = :ets.tab2list(claims_table_atom(lattice_prefix))

    for {_pk, claims} <- tbl,
        do: claims
  end
end
