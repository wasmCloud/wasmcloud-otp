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
    # TODO: for large numbers of actors this heartbeat becomes prohibitively large and expensive
    # refactor to only emit instance count
    actors =
      config.host_key
      |> ActorSupervisor.all_actors_for_hb()
      |> Enum.map(fn {k, iid} -> %{public_key: k, instance_id: iid} end)

    providers =
      config.host_key
      |> ProviderSupervisor.all_providers()
      |> Enum.map(fn {_pid, pk, link, contract, instance_id} ->
        %{public_key: pk, link_name: link, contract_id: contract, instance_id: instance_id}
      end)

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
