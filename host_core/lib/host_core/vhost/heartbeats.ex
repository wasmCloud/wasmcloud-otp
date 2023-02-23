defmodule HostCore.Vhost.Heartbeats do
  @moduledoc """
  Responsible for the generation of heartbeats. Note that publication of heartbeats is done by the
  virtual host from which the heartbeat eminates.
  """

  @thirty_seconds 30_000

  use GenServer, restart: :transient

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.CloudEvent
  alias HostCore.Providers.ProviderSupervisor
  alias Timex.Format.Duration.Formatters.Humanized

  def start_link(host_pid, host_key) when is_pid(host_pid) do
    GenServer.start_link(__MODULE__, {host_pid, host_key}, name: String.to_atom("hb-#{host_key}"))
  end

  @impl true
  def init({host_pid, host_key}) do
    :timer.send_interval(@thirty_seconds, self(), :publish_heartbeat)

    {:ok, {host_pid, host_key}}
  end

  @impl true
  def handle_info(:publish_heartbeat, state) do
    publish_heartbeat(elem(state, 0))
    {:noreply, state}
  end

  def publish_heartbeat(host_pid) do
    if Process.alive?(host_pid) do
      state = HostCore.Vhost.VirtualHost.full_state(host_pid)

      state
      |> generate_heartbeat()
      |> CloudEvent.publish(state.config.lattice_prefix)
    end
  end

  def generate_heartbeat(state) do
    config = state.config

    actors =
      config.host_key
      |> ActorSupervisor.all_actors_for_hb()

    providers =
      config.host_key
      |> ProviderSupervisor.all_providers_for_hb()

    {total, _} = :erlang.statistics(:wall_clock)
    ut_seconds = div(total - state.start_time, 1000)

    ut_human =
      ut_seconds
      |> Timex.Duration.from_seconds()
      |> Humanized.format()

    version = :host_core |> Application.spec(:vsn) |> to_string()

    CloudEvent.new(
      %{
        actors: actors,
        providers: providers,
        labels: state.labels,
        friendly_name: state.friendly_name,
        version: version,
        uptime_seconds: ut_seconds,
        uptime_human: ut_human
      },
      "host_heartbeat",
      config.host_key
    )
  end
end
