defmodule HostCore.Linkdefs.Manager do
  require Logger

  @spec lookup_link_definition(any, any, any) :: :error | {:ok, tuple}
  def lookup_link_definition(actor, contract_id, link_name) do
    case :ets.lookup(:linkdef_table, {actor, contract_id, link_name}) do
      [ld] -> {:ok, ld}
      [] -> :error
    end
  end

  def cache_link_definition(ldid, actor, contract_id, link_name, provider_key, values) do
    key = {actor, contract_id, link_name}
    map = %{values: values, id: ldid, provider_key: provider_key}
    :ets.insert(:linkdef_table, {key, map})
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
      values: values
    }

    publish_link_definition(ld)
  end

  # Publishes a link definition to the lattice and the applicable provider for configuration
  defp publish_link_definition(ld) do
    prefix = HostCore.Host.lattice_prefix()
    cache_topic = "lc.#{prefix}.linkdefs.#{ld.id}"
    provider_topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.put"

    Gnat.pub(:control_nats, cache_topic, Jason.encode!(ld))
    Gnat.pub(:lattice_nats, provider_topic, Msgpax.pack!(ld))
  end

  def get_link_definitions() do
    :ets.tab2list(:linkdef_table)
    |> Enum.map(fn {{pk, contract, link}, %{provider_key: provider_key, values: values}} ->
      %{
        actor_id: pk,
        provider_id: provider_key,
        link_name: link,
        contract_id: contract,
        values: values
      }
    end)
  end
end
