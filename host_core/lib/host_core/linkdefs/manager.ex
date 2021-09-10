defmodule HostCore.Linkdefs.Manager do
  require Logger

  @spec lookup_link_definition(String.t(), String.t(), String.t()) :: :error | {:ok, map()}
  def lookup_link_definition(actor, contract_id, link_name) do
    case :ets.lookup(:linkdef_table, {actor, contract_id, link_name}) do
      [{_key, ld}] -> {:ok, ld}
      [] -> :error
    end
  end

  def cache_link_definition(ldid, actor, contract_id, link_name, provider_key, values) do
    key = {actor, contract_id, link_name}

    map = %{
      actor_id: actor,
      contract_id: contract_id,
      link_name: link_name,
      provider_id: provider_key,
      values: values,
      id: ldid
    }

    :ets.insert(:linkdef_table, {key, map})
  end

  def uncache_link_definition(actor, contract_id, link_name) do
    key = {actor, contract_id, link_name}
    :ets.delete(:linkdef_table, key)
  end

  def put_link_definition(actor, contract_id, link_name, provider_key, values) do
    ldid = UUID.uuid4()
    cache_link_definition(ldid, actor, contract_id, link_name, provider_key, values)

    ld = %{
      id: ldid,
      actor_id: actor,
      provider_id: provider_key,
      link_name: link_name,
      contract_id: contract_id,
      values: values,
      deleted: false
    }

    publish_link_definition(ld)
  end

  def del_link_definition(actor, contract_id, link_name) do
    case lookup_link_definition(actor, contract_id, link_name) do
      {:ok, linkdef} ->
        uncache_link_definition(actor, contract_id, link_name)
        publish_link_definition_deleted(linkdef)

      :error ->
        Logger.warn(
          "Attempted to remove non-existent linkdef #{actor}-#{contract_id}-#{link_name}"
        )
    end
  end

  # Publishes a link definition to the lattice and the applicable provider for configuration
  defp publish_link_definition(ld) do
    prefix = HostCore.Host.lattice_prefix()
    cache_topic = "lc.#{prefix}.linkdefs.#{ld.id}"
    provider_topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.put"

    ldres = Gnat.pub(:control_nats, cache_topic, Jason.encode!(ld))
    lattice_res = Gnat.pub(:lattice_nats, provider_topic, Msgpax.pack!(ld))
  end

  # Publishes the removal of a link definition to the stream and tells the provider via RPC
  # to remove applicable resources
  # NOTE: publishing a linkdef removal involves re-publishing the original linkdef message
  # to its original topic with the "deleted: true" field, which will tell the cache loader
  # to uncache the item rather than cache it.
  defp publish_link_definition_deleted(ld) do
    prefix = HostCore.Host.lattice_prefix()
    cache_topic = "lc.#{prefix}.linkdefs.#{ld.id}"
    provider_topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.del"
    Gnat.pub(:lattice_nats, provider_topic, Msgpax.pack!(ld))
    ld = Map.put(ld, :deleted, true)
    Gnat.pub(:control_nats, cache_topic, Jason.encode!(ld))
  end

  def get_link_definitions() do
    :ets.tab2list(:linkdef_table)
    |> Enum.map(fn {{pk, contract, link}, %{provider_id: provider_id, values: values}} ->
      %{
        actor_id: pk,
        provider_id: provider_id,
        link_name: link,
        contract_id: contract,
        values: values
      }
    end)
  end
end
