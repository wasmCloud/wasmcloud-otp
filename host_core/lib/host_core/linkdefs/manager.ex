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

  @spec lookup_link_definition(any, any, any) :: :error | {:ok, tuple}
  def lookup_link_definition(actor, contract_id, link_name) do
    case :ets.lookup(:linkdef_table, {actor, contract_id, link_name}) do
      [ld] -> {:ok, ld}
      [] -> :error
    end
  end

  def cache_link_definition(actor, contract_id, link_name, provider_key, values) do
    key = {actor, contract_id, link_name}
    map = %{values: values, provider_key: provider_key}
    :ets.insert(:linkdef_table, {key, map})
  end

  def put_link_definition(actor, contract_id, link_name, provider_key, values) do
    cache_link_definition(actor, contract_id, link_name, provider_key, values)

    ld = %{
      actor_id: actor,
      provider_id: provider_key,
      link_name: link_name,
      contract_id: contract_id,
      values: values
    }

    publish_link_definition(ld)
  end

  def request_link_definitions() do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.linkdefs.get"

    case Gnat.request(:lattice_nats, topic, [], receive_timeout: 2_000) do
      {:ok, %{body: body}} ->
        # Unpack linkdefs, convert to map with atom keys
        Msgpax.unpack!(body)
        |> Enum.map(fn linkdefs ->
          linkdefs
          |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
        end)

      {:error, :timeout} ->
        Logger.debug("No response for linkdefs get, starting with empty linkdefs cache")
        []

      _ ->
        []
    end
  end

  # Publishes a link definition to the lattice and the applicable provider for configuration
  defp publish_link_definition(ld) do
    prefix = HostCore.Host.lattice_prefix()
    rpc_topic = "wasmbus.rpc.#{prefix}.linkdefs.put"
    provider_topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.put"

    Gnat.pub(:lattice_nats, rpc_topic, Msgpax.pack!(ld))
    Gnat.pub(:lattice_nats, provider_topic, Msgpax.pack!(ld))
  end
end
