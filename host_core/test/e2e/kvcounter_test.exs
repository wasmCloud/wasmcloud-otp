defmodule HostCore.E2E.KVCounterTest do
  use ExUnit.Case, async: false
  import HostCoreTest.Common, only: [request_http: 2]

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  require Logger

  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @kvcounter_path HostCoreTest.Constants.kvcounter_path()

  @kvcounter_unpriv_key HostCoreTest.Constants.kvcounter_unpriv_key()
  @kvcounter_unpriv_path HostCoreTest.Constants.kvcounter_unpriv_path()

  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @keyvalue_contract HostCoreTest.Constants.keyvalue_contract()
  @redis_link HostCoreTest.Constants.default_link()
  @redis_path HostCoreTest.Constants.redis_path()
  @redis_key HostCoreTest.Constants.redis_key()

  test "kvcounter roundtrip", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)

    # uncomment the before and after delays if you want this test to
    # reliably emit trace exports
    # :timer.sleep(6000)

    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @kvcounter_key)

    # NOTE: Link definitions are put _before_ providers are started so that they receive
    # the linkdef on startup. There is a race condition between provider starting and
    # creating linkdef subscriptions that make this a desirable order for consistent tests.

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: "8081"}
      )

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        @keyvalue_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_key,
        @keyvalue_contract,
        @redis_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_key,
        @httpserver_contract,
        @httpserver_link
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        @keyvalue_contract,
        @redis_link,
        @redis_key
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key)
      |> length

    assert actor_count == 1

    ap = HostCore.Providers.ProviderSupervisor.all_providers()
    assert length(ap) == 2
    assert Enum.any?(ap, fn { _, p, _, _, _ } -> p == @httpserver_key end)
    assert Enum.any?(ap, fn { _, p, _, _, _ } -> p == @redis_key end)

    {:ok, _okay} = HTTPoison.start()
    {:ok, resp} = request_http("http://localhost:8081/foobar", 5)
    # Retrieve current count, assert next request increments by 1
    {:ok, body} = resp.body |> JSON.decode()
    incr_count = Map.get(body, "counter") + 1
    {:ok, resp} = request_http("http://localhost:8081/foobar", 2)
    assert resp.body == "{\"counter\":#{incr_count}}"

    # :timer.sleep(6000)
  end

  test "kvcounter unprivileged access denied", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@kvcounter_unpriv_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @kvcounter_unpriv_key)

    # NOTE: Link definitions are put _before_ providers are started so that they receive
    # the linkdef on startup. There is a race condition between provider starting and
    # creating linkdef subscriptions that make this a desirable order for consistent tests.

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: "8082"}
      )

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        @keyvalue_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_unpriv_key,
        @keyvalue_contract,
        @redis_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_unpriv_key,
        @httpserver_contract,
        @httpserver_link
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_unpriv_key)
      |> length

    assert actor_count == 1

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        @keyvalue_contract,
        @redis_link,
        @redis_key
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key
      )

    ap = HostCore.Providers.ProviderSupervisor.all_providers()
    assert elem(Enum.at(ap, 0), 1) == @httpserver_key
    assert elem(Enum.at(ap, 1), 1) == @redis_key

    {:ok, _okay} = HTTPoison.start()
    {:ok, resp} = request_http("http://localhost:8082/foobar", 10)

    assert resp.body ==
             "{\"error\":\"Host send error Invocation not authorized: missing capability claim for wasmcloud:keyvalue\"}"

    assert resp.status_code == 500
  end
end
