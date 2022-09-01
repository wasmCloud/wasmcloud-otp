defmodule HostCore.E2E.EchoTest do
  use ExUnit.Case, async: false
  import HostCoreTest.Common, only: [request_http: 2]

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())
    on_exit(fn ->
      :ets.delete_all_objects(:linkdef_table)
    end)
    [
      evt_watcher: evt_watcher
    ]
  end

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_unpriv_key HostCoreTest.Constants.echo_unpriv_key()
  @echo_unpriv_path HostCoreTest.Constants.echo_unpriv_path()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()

  test "echo roundtrip", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @echo_key)

    # NOTE: Link definitions are put _before_ providers are started so that they receive
    # the linkdef on startup. There is a race condition between provider starting and
    # creating linkdef subscriptions that make this a desirable order for consistent tests.

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @echo_key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: "8080"}
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @echo_key,
        @httpserver_contract,
        @httpserver_link
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key)
      |> length

    assert actor_count == 1

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 1) ==
             @httpserver_key

    {:ok, _okay} = HTTPoison.start()
    {:ok, _resp} = request_http("http://localhost:8080/foo/bar", 5)
  end

  test "unprivileged actor cannot receive undeclared invocations", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)

    {:ok, bytes} = File.read(@echo_unpriv_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @echo_unpriv_key)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_unpriv_key)
      |> length

    assert actor_count == 1

    # OK to put link definition with no claims information
    assert HostCore.Linkdefs.Manager.put_link_definition(
             @echo_unpriv_key,
             @httpserver_contract,
             @httpserver_link,
             @httpserver_key,
             %{PORT: "8884"}
           ) == :ok

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key
      )

    {:ok, _okay} = HTTPoison.start()
    {:ok, resp} = request_http("http://localhost:8884/foobar", 10)

    assert resp.body == ""
    assert resp.status_code == 500
  end
end
