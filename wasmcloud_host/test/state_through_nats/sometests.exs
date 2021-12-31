defmodule WasmcloudHostTest do
  use ExUnit.Case

  require Logger
  require Poison

  test "get complete state to send to wadm via nats" do

    {:ok, gnat} = Gnat.start_link(%{host: '172.18.0.1', port: 4222})
    {:ok, _sub} = Gnat.sub(gnat, self(), "lattice_state_request") # WADM is the publishe

    # test_data =
    #   %{
    #     specversion: "1.0",
    #     # time: stamp,
    #     type: "com.wasmcloud.lattice",
    #     source: "host",
    #     datacontenttype: "application/json",
    #     id: UUID.uuid4(),
    #     data: "data"
    #   }
    #   |> Cloudevents.from_map!()
    #   |> Cloudevents.to_json() cannot encode state when data is state so uisng poison for this test

    receive do
      {:msg, %{body: _body, topic: "lattice_state_request", reply_to: nil}} ->
        state = WasmcloudHost.Lattice.StateMonitor.get_complete_state()
        json_state = Poison.encode!(state)
        :ok = Gnat.pub(gnat, "lattice_state_response", json_state)
      after
        2_000 -> "A message was not recieved during the test"
    end
  end
end
