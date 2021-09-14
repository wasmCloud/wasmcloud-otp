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
  @echo_old_oci_reference HostCoreTest.Constants.echo_ociref()
  @echo_oci_reference HostCoreTest.Constants.echo_ociref_updated()

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  test "live update same revision fails" do
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_oci_reference)

    on_exit(fn ->
      HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1)
    end)

    assert {:error, :error} == HostCore.Actors.ActorSupervisor.live_update(@echo_oci_reference)
  end

  test "live update with new revision succeeds" do
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_old_oci_reference)

    assert :ok == HostCore.Actors.ActorSupervisor.live_update(@echo_oci_reference)

    on_exit(fn ->
      HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1)
    end)

    {_pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

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
      case Gnat.request(:lattice_nats, topic, inv, receive_timeout: 2_000) do
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
    {:ok, bytes} = File.read(HostCoreTest.Constants.kvcounter_path())
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

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

  test "can invoke the echo actor" do
    {:ok, bytes} = File.read(HostCoreTest.Constants.echo_path())
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    {_pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

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
      case Gnat.request(:lattice_nats, topic, inv, receive_timeout: 2_000) do
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

  test "can invoke echo via OCI reference" do
    {:ok, pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_oci_reference)
    assert Process.alive?(pid)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key)
      |> length

    assert actor_count == 1

    {_pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

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
      case Gnat.request(:lattice_nats, topic, inv, receive_timeout: 2_000) do
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

  test "can invoke via call alias" do
    {:ok, bytes} = File.read("test/fixtures/actors/ponger_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, bytes} = File.read("test/fixtures/actors/pinger_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    on_exit(fn ->
      # Ponger
      HostCore.Actors.ActorSupervisor.terminate_actor(
        "MBMOM2EZZICFYM4KATRMH2JUO5QWE3YWCHGFZVRQQ2SQI4I5BKWIGMBS",
        1
      )

      # Pinger
      HostCore.Actors.ActorSupervisor.terminate_actor(
        "MDCX6E7RPUXSX5TJUD34CALXJJKV46MWJ2BUJQGWDDR3IYRJIWNUQ5PN",
        1
      )
    end)

    {_pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

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
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HandleRequest",
        req
      )

    pinger_key = "MDCX6E7RPUXSX5TJUD34CALXJJKV46MWJ2BUJQGWDDR3IYRJIWNUQ5PN"
    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{pinger_key}"

    res =
      case Gnat.request(:lattice_nats, topic, inv, receive_timeout: 2_000) do
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
end
