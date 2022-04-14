defmodule HostCore.ActorsTest do
  # Any test suite that relies on things like querying the actor count or the provider
  # count will need to be _synchronous_ tests so that other tests that rely on that same
  # information won't get bad/confusing results.
  use ExUnit.Case, async: false

  doctest HostCore.Actors

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_old_oci_reference HostCoreTest.Constants.echo_ociref()
  @echo_oci_reference HostCoreTest.Constants.echo_ociref_updated()
  @kvcounter_path HostCoreTest.Constants.kvcounter_path()

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  @pinger_key HostCoreTest.Constants.pinger_key()

  test "live update same revision fails", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    :ets.delete(:refmap_table, @echo_oci_reference)
    :ets.delete(:refmap_table, @echo_old_oci_reference)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_oci_reference)

    assert {:error, :error} == HostCore.Actors.ActorSupervisor.live_update(@echo_oci_reference)
  end

  test "live update with new revision succeeds", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    :ets.delete(:refmap_table, @echo_oci_reference)
    :ets.delete(:refmap_table, @echo_old_oci_reference)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_old_oci_reference)

    assert :ok == HostCore.Actors.ActorSupervisor.live_update(@echo_oci_reference)

    seed = HostCore.Host.cluster_seed()

    req =
      %{
        body: "hello",
        header: %{},
        path: "/",
        queryString: "",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    inv =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HttpServer.HandleRequest",
        req
      )

    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_key}"

    res =
      case HostCore.Nats.safe_req(:lattice_nats, topic, inv, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    assert res != :fail

    ir = res |> Msgpax.unpack!()

    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["statusCode"] == 200

    assert payload["body"] ==
             "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
  end

  test "can load actors", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pids} = HostCore.Actors.ActorSupervisor.start_actor(bytes, "", 5)

    :ok =
      HostCoreTest.EventWatcher.wait_for_event(
        evt_watcher,
        :actor_started,
        %{"public_key" => @kvcounter_key},
        5
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key)
      |> length

    assert actor_count == 5
    HostCore.Actors.ActorSupervisor.terminate_actor(@kvcounter_key, 5)

    :ok =
      HostCoreTest.EventWatcher.wait_for_event(
        evt_watcher,
        :actor_stopped,
        %{"public_key" => @kvcounter_key},
        5
      )

    assert Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key) == nil
  end

  test "can invoke the echo actor with huge payload", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    :ets.delete(:refmap_table, @echo_oci_reference)
    :ets.delete(:refmap_table, @echo_old_oci_reference)
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    req =
      %{
        body:
          Stream.repeatedly(fn -> Enum.random(["hello", "world", "foo", "bar"]) end)
          |> Enum.take(300_000)
          |> Enum.join(" "),
        header: %{},
        path: "/",
        queryString: "",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    seed = HostCore.Host.cluster_seed()

    inv =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HttpServer.HandleRequest",
        req
      )

    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_key}"

    res =
      case HostCore.Nats.safe_req(:lattice_nats, topic, inv, receive_timeout: 12_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    assert res != :fail
    ir = res |> Msgpax.unpack!()

    ir =
      case HostCore.WasmCloud.Native.dechunk_inv("#{ir["invocation_id"]}-r") do
        {:ok, resp} -> Map.put(ir, "msg", resp)
        {:error, _e} -> :fail
      end

    assert ir != :fail

    # NOTE: this is using "magic knowledge" that the HTTP server provider is using
    # msgpack to communicate with actors
    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["statusCode"] == 200
  end

  test "can invoke the echo actor", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    :ets.delete(:refmap_table, @echo_oci_reference)
    :ets.delete(:refmap_table, @echo_old_oci_reference)
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    seed = HostCore.Host.cluster_seed()

    req =
      %{
        body: "hello",
        header: %{},
        path: "/",
        queryString: "",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    inv =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HttpServer.HandleRequest",
        req
      )

    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_key}"

    res =
      case HostCore.Nats.safe_req(:lattice_nats, topic, inv, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    assert res != :fail
    HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1)

    ir = res |> Msgpax.unpack!()

    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["statusCode"] == 200

    assert payload["body"] ==
             "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
  end

  test "can invoke echo via OCI reference", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    :ets.delete(:refmap_table, @echo_oci_reference)
    :ets.delete(:refmap_table, @echo_old_oci_reference)
    {:ok, pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_oci_reference, 1)
    assert Process.alive?(pid |> List.first())

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key)
      |> length

    assert actor_count == 1

    seed = HostCore.Host.cluster_seed()

    req =
      %{
        body: "hello",
        header: %{},
        path: "/",
        queryString: "",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    inv =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :actor,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HttpServer.HandleRequest",
        req
      )

    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_key}"

    res =
      case HostCore.Nats.safe_req(:lattice_nats, topic, inv, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    assert res != :fail
    HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1)

    ir = res |> Msgpax.unpack!()

    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["statusCode"] == 200

    assert payload["body"] ==
             "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
  end

  test "can invoke via call alias", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read("test/fixtures/actors/ponger_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, bytes} = File.read("test/fixtures/actors/pinger_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    seed = HostCore.Host.cluster_seed()

    req =
      %{
        body: "",
        header: %{},
        path: "/",
        queryString: "",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    inv =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :actor,
        @pinger_key,
        @httpserver_contract,
        @httpserver_link,
        "HandleRequest",
        req
      )

    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@pinger_key}"

    res =
      case HostCore.Nats.safe_req(:lattice_nats, topic, inv, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    assert res != :fail

    ir = res |> Msgpax.unpack!()

    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["status"] == "OK"
    assert payload["statusCode"] == 200

    assert payload["body"] ==
             "{\"value\":53}"
  end

  test "Prevents an attempt to start an actor with a conflicting OCI reference", %{
    :evt_watcher => _evt_watcher
  } do
    on_exit(fn -> HostCore.Host.purge() end)
    # NOTE the reason we block this is because the only supported path to change
    # an actor's OCI reference should be through the live update process, which includes
    # the "is a valid upgrade path" check

    :ets.delete(:refmap_table, @echo_oci_reference)
    :ets.delete(:refmap_table, @echo_old_oci_reference)

    {:ok, pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_oci_reference, 1)
    assert Process.alive?(pid |> List.first())

    res = HostCore.Actors.ActorSupervisor.start_actor_from_oci("wasmcloud.azurecr.io/echo:0.3.0")

    assert res ==
             {:error,
              "Cannot start new instance of MBCFOPM6JW2APJLXJD3Z5O4CN7CPYJ2B4FTKLJUR5YR5MITIU7HD3WD5 from OCI 'wasmcloud.azurecr.io/echo:0.3.0', it is already running with different OCI reference. To upgrade an actor, use live update."}
  end

  test "stop with zero count terminates all", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pids} = HostCore.Actors.ActorSupervisor.start_actor(bytes, "", 5)

    :ok =
      HostCoreTest.EventWatcher.wait_for_event(
        evt_watcher,
        :actor_started,
        %{"public_key" => @kvcounter_key},
        5
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key)
      |> length

    assert actor_count == 5
    HostCore.Actors.ActorSupervisor.terminate_actor(@kvcounter_key, 0)

    :ok =
      HostCoreTest.EventWatcher.wait_for_event(
        evt_watcher,
        :actor_stopped,
        %{"public_key" => @kvcounter_key},
        5
      )

    assert Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key) == nil
  end
end
