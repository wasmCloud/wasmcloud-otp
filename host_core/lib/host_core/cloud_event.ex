defmodule HostCore.CloudEvent do
  @moduledoc false
  alias Phoenix.PubSub

  require Logger

  def new(data, event_type, host) do
    stamp = DateTime.utc_now() |> DateTime.to_iso8601()

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

  def publish(evt, lattice_prefix) when is_binary(evt) do
    HostCore.Nats.safe_pub(
      HostCore.Nats.control_connection(lattice_prefix),
      "wasmbus.evt.#{lattice_prefix}",
      evt
    )

    Task.Supervisor.start_child(ControlInterfaceTaskSupervisor, fn ->
      PubSub.broadcast(:hostcore_pubsub, "latticeevents:#{lattice_prefix}", {:lattice_event, evt})
    end)

    :ok
  end

  def publish(_, _), do: :ok
end
