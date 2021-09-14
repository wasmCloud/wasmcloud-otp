defmodule HostCore.E2E.EchoTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @echo_key HostCoreTest.Constants.echo_key()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()

  test "echo roundtrip", %{:evt_watcher => evt_watcher} do
    {:ok, bytes} = File.read(HostCoreTest.Constants.echo_path())
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1) end)

    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @echo_key)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key)
      |> length

    assert actor_count == 1

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 0) ==
             httpserver_key

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @echo_key,
        httpserver_contract,
        @httpserver_link,
        httpserver_key,
        %{PORT: "8080"}
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @echo_key,
        httpserver_contract,
        @httpserver_link
      )

    HTTPoison.start()
    {:ok, _resp} = HTTPoison.get("http://localhost:8080/foo/bar")
  end
end
