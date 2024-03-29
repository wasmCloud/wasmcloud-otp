defmodule HostCore.Jetstream.LegacyCacheLoader do
  @moduledoc """
  The legacy cache loader is responsible for loading metadata from the deprecated LATTICECACHE_{prefix} stream
  into the in-memory caches for claims, oci refs, call aliases, and linkdefs.
  """

  alias Phoenix.PubSub

  require Logger
  #  use Gnat.Server

  import HostCore.ControlInterface.LatticeServer, only: [failure_ack: 1]

  alias HostCore.Jetstream.Client, as: JetstreamClient
  alias HostCore.Linkdefs.Manager, as: LinkdefsManager

  def handle_legacy_request(js_domain, topic, body) do
    case String.split(topic, ".", parts: 3) do
      [_lc, prefix, remainder] ->
        remainder
        |> String.split(".")
        |> List.to_tuple()
        |> handle_request(body, prefix, js_domain)

      _ ->
        {:reply, failure_ack("Invalid request topic")}
    end

    {:reply, ""}
  end

  def handle_request({"linkdefs", key}, body, prefix, js_domain) do
    case Jason.decode(body, keys: :atoms) do
      {:ok, %{deleted: true} = ld} ->
        Logger.debug(
          "Skipping migration of deleted linkdef from #{ld.actor_id} to #{ld.provider_id}"
        )

      {:ok, ld} ->
        ld = LinkdefsManager.reidentify_linkdef(ld)

        JetstreamClient.kv_put(
          prefix,
          js_domain,
          "LINKDEF_#{ld.id}",
          Jason.encode!(ld)
        )

        Logger.debug(
          "Migrated legacy link definition #{key} from #{ld.actor_id} to #{ld.provider_id}"
        )

        broadcast_event(:linkdef_added, ld, prefix)

      {:error, e} ->
        Logger.error("Unable to parse incoming link command: #{e}")
    end
  end

  def handle_request({"claims", key}, body, prefix, js_domain) do
    case Jason.decode(body, keys: :atoms) do
      {:ok, claims} ->
        JetstreamClient.kv_put(
          prefix,
          js_domain,
          "CLAIMS_#{key}",
          Jason.encode!(claims)
        )

        broadcast_event(:claims_added, claims, prefix)

      {:error, e} ->
        Logger.error("Failed to migrate claims from legacy cache for '#{key}': #{inspect(e)}")
    end
  end

  def handle_request({"refmap", _key}, body, prefix, js_domain) do
    case Jason.decode(body, keys: :atoms) do
      {:ok, refmap} ->
        JetstreamClient.kv_put(
          prefix,
          js_domain,
          "REFMAP_#{HostCore.Nats.sanitize_for_topic(refmap.oci_url)}",
          Jason.encode!(refmap)
        )

        broadcast_event(:refmap_added, refmap, prefix)

      {:error, e} ->
        Logger.error("Failed to migrate refmap from legacy cache: #{inspect(e)}")
    end
  end

  def handle_request({keytype, _key}, _body, prefix) do
    Logger.error(
      "Jetstream cache loader encountered an unexpected key type: #{keytype} on lattice #{prefix}"
    )
  end

  defp broadcast_event(evt_type, payload, prefix) do
    PubSub.broadcast(:hostcore_pubsub, "cacheloader:#{prefix}", {:cacheloader, evt_type, payload})
  end
end
