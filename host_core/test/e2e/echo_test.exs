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
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_unpriv_key HostCoreTest.Constants.echo_unpriv_key()
  @echo_unpriv_path HostCoreTest.Constants.echo_unpriv_path()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()

  test "echo roundtrip", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

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

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 1) ==
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

  test "unprivileged actor cannot receive undeclared invocations", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)

    {:ok, bytes} = File.read(@echo_unpriv_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @echo_unpriv_key)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_unpriv_key)
      |> length

    assert actor_count == 1

    {:ok, bytes} = File.read(@httpserver_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    # OK to put link definition with no claims information
    assert HostCore.Linkdefs.Manager.put_link_definition(
             @echo_key,
             httpserver_contract,
             @httpserver_link,
             httpserver_key,
             %{PORT: "8083"}
           ) == :ok

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    # For now, okay to put a link definition without proper claims
    assert HostCore.Linkdefs.Manager.put_link_definition(
             @echo_unpriv_key,
             httpserver_contract,
             @httpserver_link,
             httpserver_key,
             %{PORT: "8084"}
           ) == :ok

    HTTPoison.start()
    {:ok, resp} = HTTPoison.get("http://localhost:8084/foobar")

    assert resp.body == ""
    assert resp.status_code == 500
  end
end
