defmodule HostCore.Benchmark.EchoTest do
  # We'd rather not run this test asynchronously because it's a benchmark. We'll get better
  # results if this is the only test running at the time.
  use ExUnit.Case, async: false

  alias HostCore.Actors.ActorRpcServer
  alias HostCore.Actors.ActorSupervisor
  alias HostCore.WasmCloud.Native
  alias HostCore.Linkdefs.Manager
  alias HostCore.Providers.ProviderSupervisor

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1, request_http: 2]

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_wasi_key HostCoreTest.Constants.echo_wasi_key()
  @echo_wasi_path HostCoreTest.Constants.echo_wasi_path()

  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  describe "Benchmarking actor invocations" do
    setup :standard_setup

    test "load test with echo wasm32-unknown actor", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      # TODO: make configurable w/ benchee
      num_actors = 1
      parallel = [1, 10]

      {msg, inv, port} = setup_echo_test(config, evt_watcher, @echo_key, @echo_path, num_actors)

      {:ok, _okay} = HTTPoison.start()

      test_config = %{
        "direct_echo_request" => fn ->
          ActorRpcServer.request(msg)
        end,
        "nats_echo_request" => fn ->
          config.lattice_prefix
          |> HostCore.Nats.rpc_connection()
          |> HostCore.Nats.safe_req(msg.topic, inv, receive_timeout: 2_000)
        end,
        "http_echo_request" => fn ->
          {:ok, _resp} = request_http("http://localhost:#{port}/foo/bar", 1)
        end
      }

      HostCore.Benchmark.Common.run_benchmark(test_config, num_actors, parallel)

      assert true
    end

    test "load test with echo wasm32-wasi actor", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      # TODO: make configurable w/ benchee
      num_actors = 1
      parallel = [1, 10]
      {:ok, bytes} = File.read(@echo_wasi_path)

      {:ok, _pids} =
        ActorSupervisor.start_actor(bytes, config.host_key, config.lattice_prefix, "", num_actors)

      seed = config.cluster_seed

      {msg, inv, port} =
        setup_echo_test(config, evt_watcher, @echo_wasi_key, @echo_wasi_path, num_actors)

      {:ok, _okay} = HTTPoison.start()

      test_config = %{
        "direct_echo_request" => fn ->
          ActorRpcServer.request(msg)
        end,
        "nats_echo_request" => fn ->
          config.lattice_prefix
          |> HostCore.Nats.rpc_connection()
          |> HostCore.Nats.safe_req(msg.topic, inv, receive_timeout: 2_000)
        end,
        "http_echo_request" => fn ->
          {:ok, _resp} = request_http("http://localhost:#{port}/foo/bar", 1)
        end
      }

      HostCore.Benchmark.Common.run_benchmark(test_config, num_actors, parallel)

      assert true
    end
  end

  @spec setup_echo_test(
          config :: map(),
          evt_watcher :: any(),
          key :: binary(),
          path :: binary(),
          num_actors :: non_neg_integer()
        ) ::
          {msg :: map(), inv :: map(), port :: binary()}
  # Helper function to set up echo tests and reduce code duplication
  def setup_echo_test(config, evt_watcher, key, path, num_actors) do
    {:ok, bytes} = File.read(path)

    {:ok, _pids} =
      ActorSupervisor.start_actor(bytes, config.host_key, config.lattice_prefix, "", num_actors)

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

    port = "8081"

    # NOTE: Link definitions are put _before_ providers are started so that they receive
    # the linkdef on startup. There is a race condition between provider starting and
    # creating linkdef subscriptions that make this a desirable order for consistent tests.

    :ok =
      Manager.put_link_definition(
        config.lattice_prefix,
        key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: port}
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_linkdef(
        evt_watcher,
        key,
        @httpserver_contract,
        @httpserver_link
      )

    # Make sure we don't log too much out of the HTTPserver provider
    System.put_env("RUST_LOG", "info,warp=warn")

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
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

    msg = %{
      body: IO.iodata_to_binary(inv),
      topic: "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_wasi_key}",
      reply_to: "_INBOX.thisisatest.notinterested"
    }

    {msg, inv, port}
  end
end
