defmodule HostCore.CloudEvent do
  @moduledoc """
  A helper module for dealing with cloud events, including the consistent generation of new events as well
  as the publication of them on the appropriate topic and Gnat connection.
  """
  alias Phoenix.PubSub

  require Logger

  def new(data, event_type, host) do
    stamp = DateTime.to_iso8601(DateTime.utc_now())

    %{
      specversion: "1.0",
      time: stamp,
      type: "com.wasmcloud.lattice.#{event_type}",
      source: "#{host}",
      datacontenttype: "application/json",
      id: UUID.uuid4(),
      data: data
    }
    |> Cloudevents.from_map!()
    |> Cloudevents.to_json()
  end

  @doc """
  Publishes a cloud event (assumed to be in the JSON format produced by `Cloudevents.to_json()` over NATS and
  also publishes a copy of that event using Phoenix Pubsub to allow for interested parties within the same OTP
  application (such as the washboard and test suites) to monitor the events without needing a NATS subscription
  """
  @spec publish(evt :: binary(), lattice_prefix :: String.t(), alt_prefix :: String.t()) :: :ok
  def publish(evt, lattice_prefix, alt_prefix \\ "wasmbus.evt") when is_binary(evt) do
    Task.Supervisor.start_child(ControlInterfaceTaskSupervisor, fn ->
      lattice_prefix
      |> HostCore.Nats.control_connection()
      |> HostCore.Nats.safe_pub("#{alt_prefix}.#{lattice_prefix}", evt)

      PubSub.broadcast(:hostcore_pubsub, "latticeevents:#{lattice_prefix}", {:lattice_event, evt})
    end)

    :ok
  end
end
