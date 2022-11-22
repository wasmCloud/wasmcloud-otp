defmodule HostCore.Linkdefs.Manager do
  @moduledoc false
  require Logger

  alias HostCore.CloudEvent

  @spec lookup_link_definition(String.t(), String.t(), String.t(), String.t()) ::
          :error | {:ok, map()}
  def lookup_link_definition(lattice_prefix, actor, contract_id, link_name) do
    case :ets.lookup(table_atom(lattice_prefix), {actor, contract_id, link_name}) do
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
    key = {actor, contract_id, link_name}

    map = %{
      actor_id: actor,
      contract_id: contract_id,
      link_name: link_name,
      provider_id: provider_key,
      values: values,
      id: ldid
    }

    :ets.insert(table_atom(lattice_prefix), {key, map})
  end

  def uncache_link_definition(lattice_prefix, actor, contract_id, link_name) do
    key = {actor, contract_id, link_name}
    :ets.delete(table_atom(lattice_prefix), key)
  end

  def put_link_definition(lattice_prefix, actor, contract_id, link_name, provider_key, values) do
    ldid = UUID.uuid4()

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
      values: values,
      deleted: false
    }

    publish_link_definition(lattice_prefix, ld)
  end

  def del_link_definition(lattice_prefix, actor, contract_id, link_name) do
    case lookup_link_definition(lattice_prefix, actor, contract_id, link_name) do
      {:ok, linkdef} ->
        uncache_link_definition(lattice_prefix, actor, contract_id, link_name)
        publish_link_definition_deleted(lattice_prefix, linkdef)

      :error ->
        Logger.warn(
          "Attempted to remove non-existent linkdef #{actor}-#{contract_id}-#{link_name}",
          actor_id: actor,
          contract_id: contract_id,
          link_name: link_name
        )
    end
  end

  # Publishes a link definition to the lattice and the applicable provider for configuration
  defp publish_link_definition(prefix, ld) do
    cache_topic = "lc.#{prefix}.linkdefs.#{ld.id}"
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

    control = HostCore.Nats.control_connection(prefix)
    rpc = HostCore.Nats.rpc_connection(prefix)

    HostCore.Nats.safe_pub(control, cache_topic, Jason.encode!(ld))
    HostCore.Nats.safe_pub(rpc, provider_topic, Msgpax.pack!(ld))
  end

  # Publishes the removal of a link definition to the stream and tells the provider via RPC
  # to remove applicable resources
  # NOTE: publishing a linkdef removal involves re-publishing the original linkdef message
  # to its original topic with the "deleted: true" field, which will tell the cache loader
  # to uncache the item rather than cache it.
  defp publish_link_definition_deleted(prefix, ld) do
    cache_topic = "lc.#{prefix}.linkdefs.#{ld.id}"
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

    control = HostCore.Nats.control_connection(prefix)
    rpc = HostCore.Nats.rpc_connection(prefix)
    HostCore.Nats.safe_pub(rpc, provider_topic, Msgpax.pack!(ld))

    ld = Map.put(ld, :deleted, true)
    HostCore.Nats.safe_pub(control, cache_topic, Jason.encode!(ld))
  end

  def get_link_definitions(prefix) do
    tbl =
      table_atom(prefix)
      |> :ets.tab2list()

    for {{pk, contract, link}, %{provider_id: provider_id, values: values}} <- tbl do
      %{
        actor_id: pk,
        provider_id: provider_id,
        link_name: link,
        contract_id: contract,
        values: values
      }
    end
  end

  def table_atom(prefix) when is_binary(prefix) do
    String.to_atom("linkdef_#{prefix}")
  end
end
