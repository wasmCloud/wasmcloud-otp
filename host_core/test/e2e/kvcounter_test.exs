defmodule HostCore.E2E.KVCounterTest do
  use ExUnit.Case, async: false
  alias HostCore.Actors.ActorSupervisor
  alias HostCore.Linkdefs.Manager
  alias HostCore.Providers.ProviderSupervisor

  import HostCoreTest.Common,
    only: [actor_count: 2, request_http: 2, cleanup: 2, standard_setup: 1]

  setup :standard_setup

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

  test "kvcounter roundtrip", %{:evt_watcher => evt_watcher, :hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    # uncomment the before and after delays if you want this test to
    # reliably emit trace exports
    # :timer.sleep(6000)

    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)

    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @kvcounter_key)

    # NOTE: Link definitions are put _before_ providers are started so that they receive
    # the linkdef on startup. There is a race condition between provider starting and
    # creating linkdef subscriptions that make this a desirable order for consistent tests.

    :ok =
      Manager.put_link_definition(
        config.lattice_prefix,
        @kvcounter_key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: "8081"}
      )

    :ok =
      Manager.put_link_definition(
        config.lattice_prefix,
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
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @httpserver_path,
        @httpserver_link
      )

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
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

    actor_count = actor_count(config.host_key, @kvcounter_key)

    assert actor_count == 1

    ap = ProviderSupervisor.all_providers(config.host_key)
    assert length(ap) == 2
    assert Enum.any?(ap, fn {_, p, _, _, _} -> p == @httpserver_key end)
    assert Enum.any?(ap, fn {_, p, _, _, _} -> p == @redis_key end)

    {:ok, _okay} = HTTPoison.start()
    {:ok, resp} = request_http("http://localhost:8081/foobar", 5)
    # Retrieve current count, assert next request increments by 1
    {:ok, body} = JSON.decode(resp.body)
    incr_count = Map.get(body, "counter", 0) + 1
    {:ok, resp} = request_http("http://localhost:8081/foobar", 2)
    assert resp.body == "{\"counter\":#{incr_count}}"

    # :timer.sleep(6000)
  end

  test "kvcounter unprivileged access denied", %{
    :evt_watcher => evt_watcher,
    :hconfig => config,
    :host_pid => pid
  } do
    on_exit(fn -> cleanup(pid, config) end)

    {:ok, bytes} = File.read(@kvcounter_unpriv_path)
    {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)
    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @kvcounter_unpriv_key)

    # NOTE: Link definitions are put _before_ providers are started so that they receive
    # the linkdef on startup. There is a race condition between provider starting and
    # creating linkdef subscriptions that make this a desirable order for consistent tests.

    :ok =
      Manager.put_link_definition(
        config.lattice_prefix,
        @kvcounter_unpriv_key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: "8082"}
      )

    :ok =
      Manager.put_link_definition(
        config.lattice_prefix,
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
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @httpserver_path,
        @httpserver_link
      )

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @redis_path,
        @redis_link
      )

    actor_count = actor_count(config.host_key, @kvcounter_unpriv_key)

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

    pid =
      ProviderSupervisor.find_provider(
        config.host_key,
        @httpserver_key,
        "default"
      )

    assert is_pid(pid) && Process.alive?(pid)

    pid = ProviderSupervisor.find_provider(config.host_key, @redis_key, "default")

    assert is_pid(pid) && Process.alive?(pid)

    # :sadpanda: sometimes on github, the HTTP server hasn't finished starting before we try and use it
    Process.sleep(300)

    {:ok, _okay} = HTTPoison.start()
    {:ok, resp} = request_http("http://localhost:8082/foobar", 10)

    assert resp.body ==
             "{\"error\":\"Host send error Invocation not authorized: missing capability claim for wasmcloud:keyvalue\"}"

    assert resp.status_code == 500
  end
end
