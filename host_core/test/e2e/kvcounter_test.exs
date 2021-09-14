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

  @kvcounter_unpriv_key HostCoreTest.Constants.pinger_key()
  @kvcounter_unpriv_path HostCoreTest.Constants.pinger_path()

  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @redis_link HostCoreTest.Constants.default_link()
  @redis_path HostCoreTest.Constants.redis_path()

  test "kvcounter roundtrip", %{:evt_watcher => evt_watcher} do
    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@kvcounter_key, 1) end)

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

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    {:ok, bytes} = File.read(@redis_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    redis_key = par.claims.public_key
    redis_contract = par.contract_id

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(redis_key, @redis_link)
    end)

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
    assert elem(Enum.at(ap, 0), 0) == httpserver_key
    assert elem(Enum.at(ap, 1), 0) == redis_key

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
        %{URL: "redis://0.0.0.0:6379"}
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
    {:ok, bytes} = File.read(@kvcounter_unpriv_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@kvcounter_unpriv_key, 1) end)
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

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    {:ok, bytes} = File.read(@redis_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    redis_key = par.claims.public_key
    redis_contract = par.contract_id

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(redis_key, @redis_link)
    end)

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
    assert elem(Enum.at(ap, 0), 0) == httpserver_key
    assert elem(Enum.at(ap, 1), 0) == redis_key

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        httpserver_contract,
        @httpserver_link,
        httpserver_key,
        %{PORT: "8081"}
      )

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        redis_contract,
        @redis_link,
        redis_key,
        %{URL: "redis://0.0.0.0:6379"}
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
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")
    IO.inspect(resp)

    assert resp.body == "Guest call failed: Host error: Invocation not authorized\n"
    assert resp.status_code == 500
  end
end
