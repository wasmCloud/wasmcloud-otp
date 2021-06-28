defmodule HostCore.CloudEvent do
  def new(data, event_type) do
    stamp = DateTime.utc_now() |> DateTime.to_iso8601()
    host = HostCore.Host.host_key()

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
end
