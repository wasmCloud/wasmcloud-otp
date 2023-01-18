defmodule HostCore.Vhost.Heartbeats do
  @moduledoc """
  Responsible for the generation of heartbeats. Note that publication of heartbeats is done by the
  virtual host from which the heartbeat eminates.
  """

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.CloudEvent
  alias HostCore.Providers.ProviderSupervisor
  alias Timex.Format.Duration.Formatters.Humanized

  def generate_heartbeat(state) do
    config = state.config

    actors =
      config.host_key
      |> ActorSupervisor.all_actors_for_hb()
      |> Map.new()

    providers =
      config.host_key
      |> ProviderSupervisor.all_providers_for_hb()

    {total, _} = :erlang.statistics(:wall_clock)
    ut_seconds = div(total, 1000)

    ut_human =
      ut_seconds
      |> Timex.Duration.from_seconds()
      |> Humanized.format()

    CloudEvent.new(
      %{
        actors: actors,
        providers: providers,
        labels: state.labels,
        friendly_name: state.friendly_name,
        version: :host_core |> Application.spec(:vsn) |> to_string(),
        uptime_seconds: ut_seconds,
        uptime_human: ut_human
      },
      "host_heartbeat",
      config.host_key
    )
  end
end
