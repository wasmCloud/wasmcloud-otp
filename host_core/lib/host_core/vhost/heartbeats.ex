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

    old_actors =
      actors
      |> Enum.map(fn {pk, count} ->
        0..count
        |> Enum.map(fn _k -> %{public_key: pk, instance_id: ""} end)
      end)

    providers =
      config.host_key
      |> ProviderSupervisor.all_providers_for_hb()

    old_providers =
      providers
      |> Enum.map(fn prov ->
        %{
          public_key: prov.public_key,
          link_name: prov.link_name,
          contract_id: "",
          instance_id: ""
        }
      end)

    {total, _} = :erlang.statistics(:wall_clock)
    ut_seconds = div(total, 1000)

    ut_human =
      ut_seconds
      |> Timex.Duration.from_seconds()
      |> Humanized.format()

    version = :host_core |> Application.spec(:vsn) |> to_string()

    [
      CloudEvent.new(
        %{
          actors: old_actors,
          providers: old_providers,
          labels: state.labels,
          friendly_name: state.friendly_name,
          version: version,
          uptime_seconds: ut_seconds,
          uptime_human: ut_human
        },
        "host_heartbeat",
        config.host_key
      ),
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
        "host_heartbeat.v2",
        config.host_key
      )
    ]
  end
end
