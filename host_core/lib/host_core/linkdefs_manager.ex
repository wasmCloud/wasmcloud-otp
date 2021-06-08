defmodule HostCore.LinkdefsManager do
  use GenServer, restart: :transient
  alias Phoenix.PubSub

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :linkdefs_manager)
  end

  @impl true
  def init(opts) do
    # subscribe to all link def add / remove operations 
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.*.*.linkdefs.*"
    {:ok, _sub} = Gnat.sub(:lattice_nats, self(), topic)

    {:ok, :ok}
  end

  @impl true
  def handle_info(
        {:msg, %{body: body, topic: topic}},
        state
      ) do
    ld = Msgpax.unpack!(body)
    cmd = topic |> String.split(".") |> Enum.at(6)
    key = {ld["actor_id"], ld["contract_id"], ld["link_name"]}
    map = %{values: ld["values"], provider_key: ld["provider_id"]}

    Logger.info("Received link definition command (#{cmd})")

    if cmd == "put" do
      :ets.insert(:linkdef_registry, {key, map})
    else
      :ets.delete(:linkdef_registry, key)
    end

    {:noreply, state}
  end

  def lookup_link_definition(actor, contract_id, link_name) do
    case :ets.lookup(:linkdef_registry, {actor, contract_id, link_name}) do
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

    :ets.insert(:linkdef_registry, {key, map})
    publish_link_definition(ld)
  end

  defp publish_link_definition(ld) do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.#{ld.provider_id}.#{ld.link_name}.linkdefs.put"
    IO.puts(topic)

    Gnat.pub(:lattice_nats, topic, Msgpax.pack!(ld))
  end
end
