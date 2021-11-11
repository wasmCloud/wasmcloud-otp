defmodule HostCore.Jetstream.CacheLoader do
  @moduledoc false
  @cache_event_key "cache_loader_events"

  # To observe cache loader events, first add the pid of the listener (a GenServer)
  # to the registry:
  # Registry.register(Registry.EventMonitorRegistry, "cache_loader_events", [])
  #
  # Then define handle_casts for the pattern {:cache_load_event, :linkdef_removed | :linkdef_added | :claims_added, data}

  require Logger
  use Gnat.Server

  def request(%{topic: topic, body: body}) do
    topic
    |> String.split(".")
    # lc
    |> List.delete_at(0)
    # {prefix}
    |> List.delete_at(0)
    # {type, key}
    |> List.to_tuple()
    |> handle_request(body)

    {:reply, ""}
  end

  def handle_request({"linkdefs", key}, body) do
    ld = body |> Jason.decode!() |> atomize

    if ld.deleted == true do
      HostCore.Linkdefs.Manager.uncache_link_definition(ld.actor_id, ld.contract_id, ld.link_name)
      Logger.debug("Removed link definition #{key} from #{ld.actor_id} to #{ld.provider_id}")
      broadcast_event(:linkdef_removed, ld)
    else
      HostCore.Linkdefs.Manager.cache_link_definition(
        key,
        ld.actor_id,
        ld.contract_id,
        ld.link_name,
        ld.provider_id,
        ld.values
      )

      Logger.debug("Cached link definition #{key} from #{ld.actor_id} to #{ld.provider_id}")
      broadcast_event(:linkdef_added, ld)
    end
  end

  def handle_request({"claims", key}, body) do
    claims = body |> Jason.decode!() |> atomize
    HostCore.Claims.Manager.cache_claims(key, claims)
    HostCore.Claims.Manager.cache_call_alias(claims.call_alias, key)

    Logger.debug("Cached claims for #{key}")
    broadcast_event(:claims_added, claims)
  end

  def handle_request({"refmap", _key}, body) do
    refmap = body |> Jason.decode!() |> atomize
    HostCore.Refmaps.Manager.cache_refmap(refmap.oci_url, refmap.public_key)

    Logger.debug("Cached OCI map reference from #{refmap.oci_url} to #{refmap.public_key}")
    broadcast_event(:refmap_added, refmap)
  end

  def handle_request({keytype, _key}, _body) do
    Logger.error("Jetstream cache loader encountered an unexpected key type: #{keytype}")
  end

  def atomize(map) do
    for {key, val} <- map, into: %{}, do: {String.to_atom(key), val}
  end

  defp broadcast_event(evt_type, payload) do
    Registry.dispatch(Registry.EventMonitorRegistry, @cache_event_key, fn entries ->
      for {pid, _} <- entries, do: GenServer.cast(pid, {:cache_load_event, evt_type, payload})
    end)
  end
end
