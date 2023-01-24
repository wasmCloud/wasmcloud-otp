defmodule HostCore.Linkdefs.Manager do
  @moduledoc false
  require Logger

  import HostCore.Jetstream.MetadataCacheLoader, only: [broadcast_event: 3]
  import HostCore.Jetstream.Client, only: [linkdef_hash: 3]

  alias HostCore.CloudEvent
  alias HostCore.Jetstream.Client, as: JetstreamClient
  alias HostCore.Lattice.LatticeSupervisor
  alias HostCore.Vhost.VirtualHost

  @spec lookup_link_definition(
          lattice_prefix :: String.t(),
          actor :: String.t(),
          contract_id :: String.t(),
          link_name :: String.t()
        ) :: map() | nil
  def lookup_link_definition(lattice_prefix, actor, contract_id, link_name) do
    case lookup_link_definition(lattice_prefix, linkdef_hash(actor, contract_id, link_name)) do
      {:ok, ld} -> ld
      :error -> nil
    end
  end

  def lookup_link_definition(lattice_prefix, ldid) do
    case :ets.lookup(table_atom(lattice_prefix), ldid) do
      [{_key, ld}] -> {:ok, ld}
      [] -> :error
    end
  end

  def reidentify_linkdef(ld) do
    Map.put(ld, :id, linkdef_hash(ld.actor_id, ld.contract_id, ld.link_name))
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
    ldid =
      if is_nil(ldid) do
        linkdef_hash(actor, contract_id, link_name)
      else
        ldid
      end

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
        with [pid | _] <- LatticeSupervisor.host_pids_in_lattice(lattice_prefix),
             config <- VirtualHost.config(pid) do
          js_domain =
            if config != nil do
              config.js_domain
            else
              nil
            end

          uncache_link_definition(lattice_prefix, linkdef.id)
          HostCore.Jetstream.Client.kv_del(lattice_prefix, js_domain, "LINKDEF_#{ldid}")
        end

        publish_link_definition_deleted(lattice_prefix, linkdef)

      :error ->
        Logger.warn("Attempted to remove non-existent linkdef #{ldid} (this is OK)")
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
    with [pid | _] <- LatticeSupervisor.host_pids_in_lattice(prefix),
         config <- VirtualHost.config(pid) do
      js_domain =
        if config != nil do
          config.js_domain
        else
          nil
        end

      JetstreamClient.kv_put(
        prefix,
        js_domain,
        "LINKDEF_#{ld.id}",
        Jason.encode!(ld)
      )
    else
      _ ->
        Logger.error(
          "Tried to find a virtual host running for lattice #{prefix} but there isn't one. This indicates corrupt state!"
        )
    end
  end

  # Publishes the removal of a link definition to the event stream and sends an indication
  # of the removal to the appropriate capability provider. Other hosts will already have been
  # informed of the deletion via key subscriptions on the bucket
  def publish_link_definition_deleted(prefix, ld) do
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
