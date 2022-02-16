defmodule HostCoreTest do
  use ExUnit.Case, async: false
  doctest HostCore

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_key HostCoreTest.Constants.echo_key()
  @httpserver_link HostCoreTest.Constants.default_link()

  test "Host purges actors and providers", %{:evt_watcher => evt_watcher} do
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    :ok =
      HostCoreTest.EventWatcher.wait_for_actor_start(
        evt_watcher,
        @echo_key
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, par} = HostCore.WasmCloud.Native.par_from_path(@httpserver_path)
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    HostCore.Host.purge()

    :ok = HostCoreTest.EventWatcher.wait_for_actor_stop(evt_watcher, @echo_key)

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )

    actor_count =
      HostCore.Actors.ActorSupervisor.all_actors()
      |> Map.keys()
      |> length

    assert actor_count == 0
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end
end
