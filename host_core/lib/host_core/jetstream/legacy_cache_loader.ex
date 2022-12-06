defmodule HostCore.Jetstream.LegacyCacheLoader do
  @moduledoc """
  The legacy cache loader is responsible for loading metadata from the deprecated LATTICECACHE_{prefix} stream
  into the in-memory caches for claims, oci refs, call aliases, and linkdefs.
  """

  alias Phoenix.PubSub

  require Logger
  use Gnat.Server

  import HostCore.ControlInterface.LatticeServer, only: [failure_ack: 1]

  def request(%{topic: topic, body: body}) do
    case String.split(topic, ".", parts: 3) do
      [_lc, prefix, remainder] ->
        remainder
        |> String.split(".")
        |> List.to_tuple()
        |> handle_request(body, prefix)

      _ ->
        {:reply, failure_ack("Invalid request topic")}
    end

    {:reply, ""}
  end

  def handle_request({"linkdefs", key}, body, prefix) do
    case Jason.decode(body, keys: :atoms) do
      {:ok, %{deleted: true} = ld} ->
        HostCore.Linkdefs.Manager.uncache_link_definition(
          prefix,
          ld.id
        )

        Logger.debug("Removed link definition #{key} from #{ld.actor_id} to #{ld.provider_id}")
        broadcast_event(:linkdef_removed, ld, prefix)

      {:ok, ld} ->
        HostCore.Linkdefs.Manager.cache_link_definition(
          prefix,
          key,
          ld.actor_id,
          ld.contract_id,
          ld.link_name,
          ld.provider_id,
          ld.values
        )

        Logger.debug("Cached link definition #{key} from #{ld.actor_id} to #{ld.provider_id}")
        broadcast_event(:linkdef_added, ld, prefix)

      {:error, e} ->
        Logger.error("Unable to parse incoming link command: #{e}")
    end
  end

  def handle_request({"claims", key}, body, prefix) do
    claims = body |> Jason.decode!() |> atomize
    HostCore.Claims.Manager.cache_claims(prefix, key, claims)
    HostCore.Claims.Manager.cache_call_alias(prefix, claims.call_alias, key)

    Logger.debug("Cached claims for #{key}")
    broadcast_event(:claims_added, claims, prefix)
  end

  def handle_request({"refmap", _key}, body, prefix) do
    refmap = body |> Jason.decode!() |> atomize
    HostCore.Refmaps.Manager.cache_refmap(prefix, refmap.oci_url, refmap.public_key)

    Logger.debug("Cached OCI map reference from #{refmap.oci_url} to #{refmap.public_key}")
    broadcast_event(:refmap_added, refmap, prefix)
  end

  def handle_request({keytype, _key}, _body, prefix) do
    Logger.error(
      "Jetstream cache loader encountered an unexpected key type: #{keytype} on lattice #{prefix}"
    )
  end

  def atomize(map) do
    for {key, val} <- map, into: %{}, do: {String.to_atom(key), val}
  end

  defp broadcast_event(evt_type, payload, prefix) do
    PubSub.broadcast(:hostcore_pubsub, "cacheloader:#{prefix}", {:cacheloader, evt_type, payload})
  end
end
