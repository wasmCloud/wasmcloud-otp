defmodule HostCore.Linkdefs.Manager do
  @moduledoc false
  require Logger

  import HostCore.Jetstream.MetadataCacheLoader, only: [broadcast_event: 3]

  alias HostCore.CloudEvent

  @spec lookup_link_definition(
          lattice_prefix :: String.t(),
          actor :: String.t(),
          contract_id :: String.t(),
          link_name :: String.t()
        ) :: map() | nil
  def lookup_link_definition(lattice_prefix, actor, contract_id, link_name) do
    predicates = [
      {:==, {:map_get, :actor_id, :"$2"}, actor},
      {:==, {:map_get, :contract_id, :"$2"}, contract_id},
      {:==, {:map_get, :link_name, :"$2"}, link_name}
    ]

    :ets.select(
      table_atom(lattice_prefix),
      [{{:"$1", :"$2"}, predicates, [:"$2"]}]
    )
    |> List.first()
  end

  def lookup_link_definition(lattice_prefix, ldid) do
    case :ets.lookup(table_atom(lattice_prefix), ldid) do
      [{_key, ld}] -> {:ok, ld}
      [] -> :error
    end
  end

  def cache_link_definition(
        lattice_prefix,
        ldid,
        actor,
        contract_id,
        link_name,
        provider_key,
        values
      ) do
    map = %{
      actor_id: actor,
      contract_id: contract_id,
      link_name: link_name,
      provider_id: provider_key,
      values: values,
      id: ldid
    }

    :ets.insert(table_atom(lattice_prefix), {ldid, map})
  end

  def cache_link_definition(lattice_prefix, ld) when is_map(ld) do
    :ets.insert(table_atom(lattice_prefix), {ld.id, ld})
  end

  def uncache_link_definition(lattice_prefix, ldid) do
    :ets.delete(table_atom(lattice_prefix), ldid)
  end

  @doc """
  This function writes the link definition data to the in-memory cache of link definitions
  and then publishes that same link definition on the wasmbus.evt ... linkdef_set topic, and
  finally sends notification of this link definition to the appropriate capability provider
  """
  def put_link_definition(
        lattice_prefix,
        actor,
        contract_id,
        link_name,
        provider_key,
        values
      ) do
    ldid = linkdef_hash(actor, contract_id, link_name)

    cache_link_definition(
      lattice_prefix,
      ldid,
      actor,
      contract_id,
      link_name,
      provider_key,
      values
    )

    ld = %{
      id: ldid,
      actor_id: actor,
      provider_id: provider_key,
      link_name: link_name,
      contract_id: contract_id,
      values: values
    }

    publish_link_definition(lattice_prefix, ld)
    write_linkdef_to_kv(lattice_prefix, ld)
  end

  def del_link_definition_by_triple(lattice_prefix, actor_id, contract_id, link_name) do
    case lookup_link_definition(lattice_prefix, actor_id, contract_id, link_name) do
      nil ->
        Logger.warn("No linkdef to delete for #{actor_id} - #{contract_id} - #{link_name}")

      %{id: ldid} ->
        del_link_definition(lattice_prefix, ldid)
    end
  end

  def del_link_definition(lattice_prefix, ldid) do
    case lookup_link_definition(lattice_prefix, ldid) do
      {:ok, linkdef} ->
        uncache_link_definition(lattice_prefix, linkdef.id)
        publish_link_definition_deleted(lattice_prefix, linkdef)

      :error ->
        Logger.warn("Attempted to remove non-existent linkdef #{ldid}")
    end
  end

  # Publishes a link definition to the lattice and the applicable provider for configuration
  # This does NOT write the linkdef to the kv bucket. That's a different operation
  def publish_link_definition(prefix, ld) do
    provider_topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.put"

    %{
      id: ld.id,
      actor_id: ld.actor_id,
      provider_id: ld.provider_id,
      link_name: ld.link_name,
      contract_id: ld.contract_id,
      values: ld.values
    }
    |> CloudEvent.new("linkdef_set", "n/a")
    |> CloudEvent.publish(prefix)

    broadcast_event(:linkdef_added, ld, prefix)

    rpc = HostCore.Nats.rpc_connection(prefix)

    HostCore.Nats.safe_pub(rpc, provider_topic, Msgpax.pack!(ld))
  end

  def write_linkdef_to_kv(prefix, ld) do
    with [pid | _] <- HostCore.Lattice.LatticeSupervisor.host_pids_in_lattice(prefix),
         config <- HostCore.Vhost.VirtualHost.config(pid) do
      js_domain =
        if config != nil do
          config.js_domain
        else
          nil
        end

      HostCore.Jetstream.Client.kv_put(
        prefix,
        js_domain,
        "LINKDEF_#{ld.id}",
        ld |> Jason.encode!()
      )
    else
      _ ->
        Logger.error(
          "Tried to find a virtual host running for lattice #{prefix} but there isn't one. This indicates corrupt state!"
        )
    end
  end

  defp linkdef_hash(actor_id, contract_id, link_name) do
    sha = :crypto.hash_init(:sha256)
    sha = :crypto.hash_update(sha, actor_id)
    sha = :crypto.hash_update(sha, contract_id)
    sha = :crypto.hash_update(sha, link_name)
    sha_binary = :crypto.hash_final(sha)
    sha_binary |> Base.encode16() |> String.upcase()
  end

  # Publishes the removal of a link definition to the event stream and sends an indication
  # of the removal to the appropriate capability provider. Other hosts will already have been
  # informed of the deletion via key subscriptions on the bucket
  defp publish_link_definition_deleted(prefix, ld) do
    provider_topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.del"

    %{
      id: ld.id,
      actor_id: ld.actor_id,
      provider_id: ld.provider_id,
      link_name: ld.link_name,
      contract_id: ld.contract_id,
      values: ld.values
    }
    |> CloudEvent.new("linkdef_deleted", "n/a")
    |> CloudEvent.publish(prefix)

    broadcast_event(:linkdef_removed, ld, prefix)

    rpc = HostCore.Nats.rpc_connection(prefix)
    HostCore.Nats.safe_pub(rpc, provider_topic, Msgpax.pack!(ld))
  end

  def get_link_definitions(prefix) do
    table_atom(prefix)
    |> :ets.tab2list()
    |> Enum.map(fn {_ldid, ld} -> ld end)
  end

  def table_atom(prefix) when is_binary(prefix) do
    String.to_atom("linkdef_#{prefix}")
  end
end
