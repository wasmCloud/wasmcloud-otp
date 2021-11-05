defmodule HostCore.E2E.KVCounterTest do
  use ExUnit.Case, async: false

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

  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @redis_link HostCoreTest.Constants.default_link()
  @redis_path HostCoreTest.Constants.redis_path()

  test "kvcounter roundtrip", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @kvcounter_key)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    {:ok, bytes} = File.read(@redis_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    redis_key = par.claims.public_key
    redis_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        redis_contract,
        @redis_link,
        redis_key
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key)
      |> length

    assert actor_count == 1

    ap = HostCore.Providers.ProviderSupervisor.all_providers()
    assert elem(Enum.at(ap, 0), 1) == httpserver_key
    assert elem(Enum.at(ap, 1), 1) == redis_key

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        httpserver_contract,
        @httpserver_link,
        httpserver_key,
        %{PORT: "8081"}
      )

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        redis_contract,
        @redis_link,
        redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_key,
        redis_contract,
        @redis_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_key,
        httpserver_contract,
        @httpserver_link
      )

    HTTPoison.start()
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")

    # Retrieve current count, assert next request increments by 1
    {:ok, body} = resp.body |> JSON.decode()
    incr_count = Map.get(body, "counter") + 1
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")
    assert resp.body == "{\"counter\":#{incr_count}}"
  end

  test "kvcounter unprivileged access denied", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@kvcounter_unpriv_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, @kvcounter_unpriv_key)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    {:ok, bytes} = File.read(@redis_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    redis_key = par.claims.public_key
    redis_contract = par.contract_id

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_unpriv_key)
      |> length

    assert actor_count == 1

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        redis_contract,
        @redis_link,
        redis_key
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    ap = HostCore.Providers.ProviderSupervisor.all_providers()
    assert elem(Enum.at(ap, 0), 1) == httpserver_key
    assert elem(Enum.at(ap, 1), 1) == redis_key

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        httpserver_contract,
        @httpserver_link,
        httpserver_key,
        %{PORT: "8082"}
      )

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        redis_contract,
        @redis_link,
        redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_unpriv_key,
        redis_contract,
        @redis_link
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        @kvcounter_unpriv_key,
        httpserver_contract,
        @httpserver_link
      )

    HTTPoison.start()

    {:ok, resp} = HTTPoison.get("http://localhost:8082/foobar")

    IO.inspect(resp)

    assert resp.body ==
             "{\"error\":\"Host send error Invocation not authorized: missing claim for wasmcloud:keyvalue\"}"

    assert resp.status_code == 500
  end
end
