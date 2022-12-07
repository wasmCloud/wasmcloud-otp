defmodule HostCore.Jetstream.MetadataCacheLoader do
  @moduledoc """
  The metadata cache loader is responsible for reading metadata key changes (add/remove) from the LATTICEDATA_{prefix}
  NATS key-value bucket.
  """
  alias HostCore.Linkdefs
  alias Phoenix.PubSub
  alias HostCore.Claims.Manager, as: ClaimsManager
  alias HostCore.Refmaps.Manager, as: RefmapsManager
  alias HostCore.Linkdefs.Manager, as: LinkdefsManager

  require Logger
  use Gnat.Server

  @operation_header "kv-operation"
  @operation_del "DEL"

  @bucket_prefix "LATTICEDATA_"
  @claims_prefix "CLAIMS_"
  @refmap_prefix "REFMAP_"
  @linkdef_prefix "LINKDEF_"

  def request(%{topic: topic, body: body, headers: headers}) do
    tokenmap = tokenize(topic)

    if {@operation_header, @operation_del} in headers do
      handle_action(:key_deleted, tokenmap, body)
    else
      handle_action(:key_added, tokenmap, body)
    end

    :ok
  end

  def request(%{topic: topic, body: body}) do
    tokenmap = tokenize(topic)

    handle_action(:key_added, tokenmap, body)
    :ok
  end

  defp handle_action(
         :key_added,
         %{key: @claims_prefix <> public_key, prefix: lattice_prefix},
         body
       ) do
    case Jason.decode(body, keys: :atoms) do
      {:ok, claims} ->
        Logger.debug("Caching claims for #{public_key}")
        ClaimsManager.cache_claims(lattice_prefix, public_key, claims)

      {:error, e} ->
        Logger.error("Failed to deserialize claims from metadata cache: #{inspect(e)}")
    end
  end

  defp handle_action(:key_added, %{key: @refmap_prefix <> _hash, prefix: lattice_prefix}, body) do
    case Jason.decode(body, keys: :atoms) do
      {:ok, refmap} ->
        Logger.debug("Caching reference map between #{refmap.oci_url} and #{refmap.public_key}")
        RefmapsManager.cache_refmap(lattice_prefix, refmap.oci_url, refmap.public_key)

      {:error, e} ->
        Logger.error("Failed to deserialize refmap from metadata cache: #{inspect(e)}")
    end
  end

  defp handle_action(:key_added, %{key: @linkdef_prefix <> _ldid, prefix: lattice_prefix}, body) do
    case Jason.decode(body, keys: :atoms) do
      {:ok, ld} ->
        Logger.debug("Caching link definition from #{ld.actor_id} on contract #{ld.contract_id}")
        Linkdefs.Manager.cache_link_definition(lattice_prefix, ld)
        Linkdefs.Manager.publish_link_definition(lattice_prefix, ld)

      {:error, e} ->
        Logger.error("Failed to deserialize linkdef from metadata cache: #{inspect(e)}")
    end
  end

  defp handle_action(:key_deleted, %{key: @linkdef_prefix <> ldid, prefix: lattice_prefix}, _body) do
    Logger.debug("Removing cached reference for linkdef ID #{ldid}")
    LinkdefsManager.del_link_definition(lattice_prefix, ldid)
  end

  defp handle_action(:key_deleted, %{key: @claims_prefix <> pk, prefix: lattice_prefix}, _body) do
    Logger.debug("Removing cached claims for #{pk}")
    ClaimsManager.uncache_claims(lattice_prefix, pk)
  end

  defp handle_action(action, tokenmap, _body) do
    IO.puts(action)
    IO.inspect(tokenmap)
  end

  defp tokenize(topic) when is_binary(topic) do
    tokens = String.split(topic, ".")

    if length(tokens) == 3 do
      # no JS domain
      %{
        key: Enum.at(tokens, 2),
        prefix: tokens |> Enum.at(1) |> String.replace(@bucket_prefix, ""),
        domain: nil
      }
    else
      # JS domain
      %{
        key: Enum.at(tokens, 3),
        prefix: tokens |> Enum.at(2) |> String.replace(@bucket_prefix, ""),
        domain: Enum.at(tokens, 1)
      }
    end
  end

  def broadcast_event(evt_type, payload, lattice_prefix) do
    PubSub.broadcast(
      :hostcore_pubsub,
      "cacheloader:#{lattice_prefix}",
      {:cacheloader, evt_type, payload}
    )
  end
end