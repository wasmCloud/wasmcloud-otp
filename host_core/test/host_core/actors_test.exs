defmodule HostCore.ActorsTest do
  # Any test suite that relies on things like querying the actor count or the provider
  # count will need to be _synchronous_ tests so that other tests that rely on that same
  # information won't get bad/confusing results.
  use ExUnit.Case, async: false

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1, actor_count: 2]
  import HostCoreTest.EventWatcher, only: [wait_for_actor_start: 2, wait_for_actor_stop: 2]

  alias HostCore.Actors.ActorModule
  alias HostCore.Actors.ActorSupervisor
  alias HostCore.WasmCloud.Native

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_wasi_key HostCoreTest.Constants.echo_wasi_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_wasi_path HostCoreTest.Constants.echo_wasi_path()
  @echo_old_oci_reference HostCoreTest.Constants.echo_ociref()
  @echo_oci_reference HostCoreTest.Constants.echo_ociref_updated()
  @kvcounter_path HostCoreTest.Constants.kvcounter_path()
  @kvcounter_unpriv_filepath HostCoreTest.Constants.kvcounter_unpriv_filepath()
  @kvcounter_unpriv_key HostCoreTest.Constants.kvcounter_unpriv_key()

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
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, _pid} = ActorSupervisor.start_actor_from_oci(config.host_key, @echo_oci_reference)

      wait_for_actor_start(evt_watcher, @echo_key)

      assert {:error, :error} ==
               ActorSupervisor.live_update(config.host_key, @echo_oci_reference)
    end

    test "live update with new revision succeeds", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, _pid} =
        ActorSupervisor.start_actor_from_oci(
          config.host_key,
          @echo_old_oci_reference
        )

      wait_for_actor_start(evt_watcher, @echo_key)

      assert :ok ==
               ActorSupervisor.live_update(config.host_key, @echo_oci_reference)

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
        Native.generate_invocation_bytes(
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
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 2_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail

      ir = Msgpax.unpack!(res)

      payload = Msgpax.unpack!(ir["msg"])

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
    end

    test "can load actors", %{:evt_watcher => evt_watcher, :hconfig => config, :host_pid => pid} do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@kvcounter_path)

      {:ok, _pids} =
        ActorSupervisor.start_actor(bytes, config.host_key, "", 5, %{
          "is_testing" => "youbetcha"
        })

      :ok = wait_for_actor_start(evt_watcher, @kvcounter_key)

      actors = ActorSupervisor.all_actors(config.host_key)
      kv_counters = Map.get(actors, @kvcounter_key)

      actor_count = length(kv_counters)

      assert kv_counters |> Enum.at(0) |> ActorModule.annotations() == %{
               "is_testing" => "youbetcha"
             }

      assert actor_count == 5
      ActorSupervisor.terminate_actor(config.host_key, @kvcounter_key, 5, %{})

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_stopped,
          %{"public_key" => @kvcounter_key},
          5
        )

      assert config.host_key |> ActorSupervisor.all_actors() |> Map.get(@kvcounter_key) == nil
    end

    test "can load actors from file", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, _pids} =
        ActorSupervisor.start_actor_from_ref(
          config.host_key,
          @kvcounter_unpriv_filepath,
          5,
          %{
            "is_testing" => "youbetcha"
          }
        )

      :ok = wait_for_actor_start(evt_watcher, @kvcounter_unpriv_key)

      actors = ActorSupervisor.all_actors(config.host_key)
      kv_counters = Map.get(actors, @kvcounter_unpriv_key)

      actor_count = length(kv_counters)

      assert kv_counters |> Enum.at(0) |> ActorModule.annotations() == %{
               "is_testing" => "youbetcha"
             }

      assert actor_count == 5
      ActorSupervisor.terminate_actor(config.host_key, @kvcounter_unpriv_key, 5, %{})

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_stopped,
          %{"public_key" => @kvcounter_unpriv_key},
          5
        )

      assert config.host_key |> ActorSupervisor.all_actors() |> Map.get(@kvcounter_unpriv_key) ==
               nil
    end

    test "can invoke the echo actor with huge payload", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_path)

      {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)
      wait_for_actor_start(evt_watcher, @echo_key)

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
        Native.generate_invocation_bytes(
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
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 12_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      ir = Msgpax.unpack!(res)

      ir =
        case Native.dechunk_inv("#{ir["invocation_id"]}-r") do
          {:ok, resp} -> Map.put(ir, "msg", resp)
          {:error, _e} -> :fail
        end

      assert ir != :fail

      # NOTE: this is using "magic knowledge" that the HTTP server provider is using
      # msgpack to communicate with actors
      payload = Msgpax.unpack!(ir["msg"])

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200
    end

    # This doesn't exercise any WASI-specific functionality, only proves that a WASI-compiled
    # module can run properly in the host
    test "can invoke the echo actor (WASI)", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_wasi_path)

      {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)
      wait_for_actor_start(evt_watcher, @echo_wasi_key)

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
        Native.generate_invocation_bytes(
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
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 2_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      ActorSupervisor.terminate_actor(config.host_key, @echo_wasi_key, 1, %{})

      ir = Msgpax.unpack!(res)

      payload = Msgpax.unpack!(ir["msg"])

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
    end

    test "can invoke the echo actor", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_path)

      {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)
      wait_for_actor_start(evt_watcher, @echo_key)

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
        Native.generate_invocation_bytes(
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
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 2_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      ActorSupervisor.terminate_actor(config.host_key, @echo_key, 1, %{})

      ir = Msgpax.unpack!(res)

      payload = Msgpax.unpack!(ir["msg"])

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
    end

    test "can invoke echo via OCI reference", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, pid} =
        ActorSupervisor.start_actor_from_oci(
          config.host_key,
          @echo_oci_reference,
          1
        )

      wait_for_actor_start(evt_watcher, @echo_key)
      assert pid |> List.first() |> Process.alive?()

      actor_count = actor_count(config.host_key, @echo_key)

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
        Native.generate_invocation_bytes(
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
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 2_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      ActorSupervisor.terminate_actor(config.host_key, @echo_key, 1, %{})

      ir = Msgpax.unpack!(res)

      payload = Msgpax.unpack!(ir["msg"])

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
    end

    test "can invoke via call alias", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read("test/fixtures/actors/ponger_s.wasm")

      {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)

      {:ok, bytes} = File.read("test/fixtures/actors/pinger_s.wasm")
      {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)
      wait_for_actor_start(evt_watcher, @pinger_key)

      Process.sleep(2_000)

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
        Native.generate_invocation_bytes(
          seed,
          "system",
          :actor,
          @pinger_key,
          @httpserver_contract,
          @httpserver_link,
          "HttpServer.HandleRequest",
          req
        )

      topic = "wasmbus.rpc.#{config.lattice_prefix}.#{@pinger_key}"

      res =
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 3_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail

      ir = Msgpax.unpack!(res)
      IO.inspect(ir)

      payload = Msgpax.unpack!(ir["msg"])

      assert payload["header"] == %{}
      assert payload["status"] == "OK"
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "{\"value\":53}"
    end

    test "Prevents an attempt to start an actor with a conflicting OCI reference", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      # NOTE the reason we block this is because the only supported path to change
      # an actor's OCI reference should be through the live update process, which includes
      # the "is a valid upgrade path" check

      {:ok, pid} =
        ActorSupervisor.start_actor_from_oci(
          config.host_key,
          @echo_oci_reference,
          1
        )

      wait_for_actor_start(evt_watcher, @echo_key)
      assert pid |> List.first() |> Process.alive?()

      res =
        ActorSupervisor.start_actor_from_oci(
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
      {:ok, _pids} = ActorSupervisor.start_actor(bytes, config.host_key, "", 5)

      wait_for_actor_start(evt_watcher, @kvcounter_key)

      actor_count = actor_count(config.host_key, @kvcounter_key)

      assert actor_count == 5
      ActorSupervisor.terminate_actor(config.host_key, @kvcounter_key, 0, %{})

      :ok =
        HostCoreTest.EventWatcher.wait_for_event(
          evt_watcher,
          :actor_stopped,
          %{"public_key" => @kvcounter_key},
          5
        )

      assert config.host_key |> ActorSupervisor.all_actors() |> Map.get(@kvcounter_key) ==
               nil
    end

    test "can invoke an actor after stopping all instances and restarting", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@echo_path)
      {:ok, _pids} = ActorSupervisor.start_actor(bytes, config.host_key, "", 5)

      wait_for_actor_start(evt_watcher, @echo_key)

      ActorSupervisor.terminate_actor(config.host_key, @echo_key, 0, %{})

      wait_for_actor_stop(evt_watcher, @echo_key)

      # restart actor

      {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)
      wait_for_actor_start(evt_watcher, @echo_key)

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
        Native.generate_invocation_bytes(
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
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 2_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail
      ActorSupervisor.terminate_actor(config.host_key, @echo_key, 0, %{})
    end

    test "can support builtin logging and numbergen invocations", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      {:ok, bytes} = File.read(@randogenlogger_path)

      {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)
      wait_for_actor_start(evt_watcher, @randogenlogger_key)

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
        Native.generate_invocation_bytes(
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
        case config.lattice_prefix
             |> HostCore.Nats.rpc_connection()
             |> HostCore.Nats.safe_req(topic, inv, receive_timeout: 2_000) do
          {:ok, %{body: body}} -> body
          {:error, :timeout} -> :fail
        end

      assert res != :fail

      ActorSupervisor.terminate_actor(
        config.host_key,
        @randogenlogger_key,
        1,
        %{}
      )

      ir = Msgpax.unpack!(res)
      payload = Msgpax.unpack!(ir["msg"])

      assert payload["header"] == %{}
      assert payload["statusCode"] == 200

      assert payload["body"] ==
               "I did it"
    end
  end
end
