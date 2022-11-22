defmodule HostCore.ActorsTest do
  # Any test suite that relies on things like querying the actor count or the provider
  # count will need to be _synchronous_ tests so that other tests that rely on that same
  # information won't get bad/confusing results.
  use ExUnit.Case, async: true

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1]

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_wasi_key HostCoreTest.Constants.echo_wasi_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_wasi_path HostCoreTest.Constants.echo_wasi_path()
  @echo_old_oci_reference HostCoreTest.Constants.echo_ociref()
  @echo_oci_reference HostCoreTest.Constants.echo_ociref_updated()
  @kvcounter_path HostCoreTest.Constants.kvcounter_path()

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  @pinger_key HostCoreTest.Constants.pinger_key()
  @randogenlogger_key HostCoreTest.Constants.randogenlogger_key()
  @randogenlogger_path HostCoreTest.Constants.randogenlogger_path()

  describe "Performing standard operations on actors" do
    setup :standard_setup

    test "live update same revision fails", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, _pid} =
        HostCore.Actors.ActorSupervisor.start_actor_from_oci(config.host_key, @echo_oci_reference)

      assert {:error, :error} ==
               HostCore.Actors.ActorSupervisor.live_update(config.host_key, @echo_oci_reference)
    end

    test "live update with new revision succeeds", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, _pid} =
        HostCore.Actors.ActorSupervisor.start_actor_from_oci(
          config.host_key,
          @echo_old_oci_reference
        )

      assert :ok ==
               HostCore.Actors.ActorSupervisor.live_update(config.host_key, @echo_oci_reference)

      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 2_000
             ) do
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

    test "can load actors", %{:evt_watcher => evt_watcher, :hconfig => config, :host_pid => pid} do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@kvcounter_path)

      {:ok, _pids} =
        HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key, "", 5, %{
          "is_testing" => "youbetcha"
        })

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_started,
          %{"public_key" => @kvcounter_key},
          5
        )

      actors = HostCore.Actors.ActorSupervisor.all_actors(config.host_key)
      kv_counters = Map.get(actors, @kvcounter_key)

      actor_count = kv_counters |> length

      assert Enum.at(kv_counters, 0) |> HostCore.Actors.ActorModule.annotations() ==
               %{"is_testing" => "youbetcha"}

      assert actor_count == 5
      HostCore.Actors.ActorSupervisor.terminate_actor(config.host_key, @kvcounter_key, 5, %{})

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_stopped,
          %{"public_key" => @kvcounter_key},
          5
        )

      assert Map.get(HostCore.Actors.ActorSupervisor.all_actors(config.host_key), @kvcounter_key) ==
               nil
    end

    test "can invoke the echo actor with huge payload", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_path)
      {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key)

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

      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 12_000
             ) do
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

    # This doesn't exercise any WASI-specific functionality, only proves that a WASI-compiled
    # module can run properly in the host
    test "can invoke the echo actor (WASI)", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_wasi_path)
      {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key)

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

      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_wasi_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 2_000
             ) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      HostCore.Actors.ActorSupervisor.terminate_actor(config.host_key, @echo_wasi_key, 1, %{})

      ir = res |> Msgpax.unpack!()

      payload = ir["msg"] |> Msgpax.unpack!()

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
    end

    test "can invoke the echo actor", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_path)
      {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key)

      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 2_000
             ) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      HostCore.Actors.ActorSupervisor.terminate_actor(config.host_key, @echo_key, 1, %{})

      ir = res |> Msgpax.unpack!()

      payload = ir["msg"] |> Msgpax.unpack!()

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
    end

    test "can invoke echo via OCI reference", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, pid} =
        HostCore.Actors.ActorSupervisor.start_actor_from_oci(
          config.host_key,
          @echo_oci_reference,
          1
        )

      assert Process.alive?(pid |> List.first())

      actor_count =
        Map.get(HostCore.Actors.ActorSupervisor.all_actors(config.host_key), @echo_key)
        |> length

      assert actor_count == 1

      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 2_000
             ) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      HostCore.Actors.ActorSupervisor.terminate_actor(config.host_key, @echo_key, 1, %{})

      ir = res |> Msgpax.unpack!()

      payload = ir["msg"] |> Msgpax.unpack!()

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
    end

    test "can invoke via call alias", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read("test/fixtures/actors/ponger_s.wasm")
      {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key)
      {:ok, bytes} = File.read("test/fixtures/actors/pinger_s.wasm")
      {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key)
      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@pinger_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 2_000
             ) do
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
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      # NOTE the reason we block this is because the only supported path to change
      # an actor's OCI reference should be through the live update process, which includes
      # the "is a valid upgrade path" check

      {:ok, pid} =
        HostCore.Actors.ActorSupervisor.start_actor_from_oci(
          config.host_key,
          @echo_oci_reference,
          1
        )

      assert Process.alive?(pid |> List.first())

      res =
        HostCore.Actors.ActorSupervisor.start_actor_from_oci(
          config.host_key,
          "wasmcloud.azurecr.io/echo:0.3.0"
        )

      assert res ==
               {:error,
                "Cannot start new instance of MBCFOPM6JW2APJLXJD3Z5O4CN7CPYJ2B4FTKLJUR5YR5MITIU7HD3WD5 from ref 'wasmcloud.azurecr.io/echo:0.3.0', it is already running with different reference. To upgrade an actor, use live update."}
    end

    test "stop with zero count terminates all", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@kvcounter_path)
      {:ok, _pids} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key, "", 5)

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_started,
          %{"public_key" => @kvcounter_key},
          5
        )

      actor_count =
        Map.get(HostCore.Actors.ActorSupervisor.all_actors(config.host_key), @kvcounter_key)
        |> length

      assert actor_count == 5
      HostCore.Actors.ActorSupervisor.terminate_actor(config.host_key, @kvcounter_key, 0, %{})

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_stopped,
          %{"public_key" => @kvcounter_key},
          5
        )

      assert Map.get(HostCore.Actors.ActorSupervisor.all_actors(config.host_key), @kvcounter_key) ==
               nil
    end

    test "can invoke an actor after stopping all instances and restarting", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_path)
      {:ok, _pids} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key, "", 5)

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_started,
          %{"public_key" => @echo_key},
          5
        )

      HostCore.Actors.ActorSupervisor.terminate_actor(config.host_key, @echo_key, 0, %{})

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_stopped,
          %{"public_key" => @echo_key},
          5
        )

      # restart actor
      {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key)

      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 2_000
             ) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      HostCore.Actors.ActorSupervisor.terminate_actor(config.host_key, @echo_key, 0, %{})
    end

    test "can support builtin logging and numbergen invocations", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@randogenlogger_path)
      {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key)

      seed = config.cluster_seed

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

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@randogenlogger_key}"

      res =
        case HostCore.Nats.safe_req(
               HostCore.Nats.rpc_connection(config.lattice_prefix),
               topic,
               inv,
               receive_timeout: 2_000
             ) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail

      HostCore.Actors.ActorSupervisor.terminate_actor(
        config.host_key,
        @randogenlogger_key,
        1,
        %{}
      )

      ir = res |> Msgpax.unpack!()
      payload = ir["msg"] |> Msgpax.unpack!()

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "I did it"
    end
  end
end
