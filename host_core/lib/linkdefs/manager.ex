defmodule HostCore.Linkdefs.Manager do
  use GenServer, restart: :transient
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :linkdefs_manager)
  end

  @impl true
  def init(_opts) do
    {:ok, :ok}
  end

  def lookup_link_definition(actor, contract_id, link_name) do
    case :ets.lookup(:linkdef_table, {actor, contract_id, link_name}) do
      [ld] -> {:ok, ld}
      [] -> :error
    end
  end

  def put_link_definition(actor, contract_id, link_name, provider_key, values) do
    key = {actor, contract_id, link_name}
    map = %{values: values, provider_key: provider_key}

    ld = %{
      actor_id: actor,
      provider_id: provider_key,
      link_name: link_name,
      contract_id: contract_id,
      values: values
    }

    :ets.insert(:linkdef_table, {key, map})
    publish_link_definition(ld)
  end

  defp publish_link_definition(ld) do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.put"

    Gnat.pub(:lattice_nats, topic, Msgpax.pack!(ld))
  end
end
