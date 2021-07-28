defmodule HostCore.HeartbeatEmitter do
  use GenServer, restart: :transient
  require Logger

  @thirty_seconds 30_000

  alias HostCore.CloudEvent

  @doc """
  Starts the host server
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Process.send_after(self(), :publish_heartbeat, @thirty_seconds)

    {:ok, opts}
  end

  @impl true
  def handle_info(:publish_heartbeat, state) do
    publish_heartbeat(state)
    Process.send_after(self(), :publish_heartbeat, @thirty_seconds)
    {:noreply, state}
  end

  def publish_heartbeat(state) do
    Logger.debug("Publishing heartbeat")
    topic = "wasmbus.evt.#{state[:lattice_prefix]}"
    msg = generate_heartbeat(state)
    Gnat.pub(:control_nats, topic, msg)
  end

  defp generate_heartbeat(state) do
    actors =
      HostCore.Actors.ActorSupervisor.all_actors()
      |> Enum.map(fn {k, v} -> %{actor: k, instances: length(v)} end)

    providers =
      HostCore.Providers.ProviderSupervisor.all_providers()
      |> Enum.map(fn {pk, link, contract, instance_id} ->
        %{public_key: pk, link_name: link, contract_id: contract, instance_id: instance_id}
      end)

    %{
      actors: actors,
      providers: providers
    }
    |> CloudEvent.new("host_heartbeat", state[:host_key])
  end
end
