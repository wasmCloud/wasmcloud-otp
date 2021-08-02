defmodule HostCore.E2E.EchoTest do
  use ExUnit.Case, async: false

  @echo_key "MADQAFWOOOCZFDKYEYHC7AUQKDJTP32XUC5TDSMN4JLTDTU2WXBVPG4G"
  @httpserver_link "default"
  @httpserver_path "test/fixtures/providers/httpserver.par.gz"

  test "echo roundtrip" do
    {:ok, bytes} = File.read("test/fixtures/actors/echo_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1) end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    par = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    Process.sleep(1000)

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key)
      |> length

    assert actor_count == 1

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 0) ==
             httpserver_key

    Process.sleep(1000)

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @echo_key,
        httpserver_contract,
        @httpserver_link,
        httpserver_key,
        %{PORT: "8080"}
      )

    Process.sleep(1000)

    HTTPoison.start()
    {:ok, _resp} = HTTPoison.get("http://localhost:8080/foo/bar")

    Process.sleep(1000)
  end
end
