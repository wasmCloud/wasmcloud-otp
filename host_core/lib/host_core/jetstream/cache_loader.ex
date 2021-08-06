defmodule HostCore.Jetstream.CacheLoader do
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
    HostCore.Linkdefs.Manager.cache_link_definition(key, ld.actor_id, ld.contract_id, ld.link_name, ld.provider_id, ld.values)

    Logger.debug("Cached link definition #{key} from #{ld.actor_id} to #{ld.provider_id}")
  end

  def handle_request({"claims", key}, body) do
    claims = body |> Jason.decode!() |> atomize
    HostCore.Claims.Manager.cache_claims(key, claims)
    HostCore.Claims.Manager.cache_call_alias(claims.call_alias, key)

    Logger.debug("Cached claims for #{key}")
  end

  def handle_request({"ocimap", _key}, body) do
    refmap = body |> Jason.decode!() |> atomize
    HostCore.Refmaps.Manager.cache_refmap(refmap.oci_url, refmap.public_key)

    Logger.debug("Cached OCI map reference from #{refmap.oci_url} to #{refmap.public_key}")
  end

  def handle_request({keytype, _key}, _body) do
    Logger.error("Jetstream cache loader encountered an unexpected key type: #{keytype}")
  end

  defp atomize(map) do
    for {key, val} <- map, into: %{}, do: {String.to_atom(key), val}
  end
end
