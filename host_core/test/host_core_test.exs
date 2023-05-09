defmodule HostCoreTest do
  use ExUnit.Case, async: false

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1]

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.Providers.ProviderSupervisor
  alias HostCore.Vhost.VirtualHost
  alias HostCore.WasmCloud.Native

  setup :standard_setup

  require Logger

  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_key HostCoreTest.Constants.echo_key()
  @httpserver_link HostCoreTest.Constants.default_link()

  test "Host purges actors and providers", %{
    :evt_watcher => evt_watcher,
    :hconfig => config,
    :host_pid => pid
  } do
    on_exit(fn -> cleanup(pid, config) end)

    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key, config.lattice_prefix)

    :ok =
      HostCoreTest.EventWatcher.wait_for_actor_start(
        evt_watcher,
        @echo_key
      )

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @httpserver_path,
        @httpserver_link
      )

    {:ok, par} = Native.par_from_path(@httpserver_path, @httpserver_link)
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    VirtualHost.purge(pid, nil)

    :ok = HostCoreTest.EventWatcher.wait_for_actor_stop(evt_watcher, @echo_key)

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )

    actor_count =
      ActorSupervisor.all_actors(config.host_key)
      |> Map.keys()
      |> length

    # Give the host a bit more time to empty the registry post-purge
    Process.sleep(500)

    assert actor_count == 0
    assert ProviderSupervisor.all_providers(config.host_key) == []
  end
end
