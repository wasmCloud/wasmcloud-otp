defmodule HostCore.BenchmarkTest do
  # We'd rather not run this test asynchronously because it's a benchmark. We'll get better
  # results if this is the only test running at the time.
  use ExUnit.Case, async: false

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.WasmCloud.Native
  alias HostCore.Linkdefs.Manager
  alias HostCore.Providers.ProviderSupervisor

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1, request_http: 2]

  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @kvcounter_path HostCoreTest.Constants.kvcounter_path()

  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @keyvalue_contract HostCoreTest.Constants.keyvalue_contract()
  @redis_link HostCoreTest.Constants.default_link()
  @redis_path HostCoreTest.Constants.redis_path()
  @redis_key HostCoreTest.Constants.redis_key()

  describe "Benchmarking actor invocations" do
    setup :standard_setup

    test "load test with kvcounter wasm32-unknown actor", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      # TODO: make configurable w/ benchee
      num_actors = 25
      parallel = [1, 10, 25, 50]

      {_msg, _inv, port} =
        setup_kvcounter_test(config, evt_watcher, @kvcounter_key, @kvcounter_path, num_actors)

      HostCoreTest.Common.pre_benchmark_run()
      # very noisy debug logs during bench
      {:ok, _okay} = HTTPoison.start()

      test_config = %{
        "http_kvcounter_request" => fn ->
          {:ok, _resp} = request_http("http://localhost:#{port}/api/counter", 1)
        end
      }

      # Run the test at a few specified levels of parallelism, allowing for some warmup time to let compute calm down
      HostCoreTest.Common.run_benchmark(test_config, num_actors, parallel)

      HostCoreTest.Common.post_benchmark_run()

      assert true
    end
  end

  @spec setup_kvcounter_test(
          config :: map(),
          evt_watcher :: any(),
          key :: binary(),
          path :: binary(),
          num_actors :: non_neg_integer()
        ) ::
          {msg :: map(), inv :: map(), port :: binary()}
  # Helper function to set up kvcounter tests and reduce code duplication
  def setup_kvcounter_test(config, evt_watcher, key, path, num_actors) do
    {:ok, bytes} = File.read(path)

    {:ok, _pids} = ActorSupervisor.start_actor(bytes, config.host_key, "", num_actors)

    seed = config.cluster_seed

    req =
      %{
        body: "hello",
        header: %{},
        path: "/api/counter",
        queryString: "",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    port = "8082"

    # Make sure we don't log too much out of the HTTPserver provider
    System.put_env("RUST_LOG", "info,warp=warn")

    :ok = HostCoreTest.EventWatcher.wait_for_actor_start(evt_watcher, key)

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
        %{PORT: port}
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
      topic: "wasmbus.rpc.#{config.lattice_prefix}.#{@kvcounter_key}",
      reply_to: "_INBOX.thisisatest.notinterested"
    }

    {msg, inv, port}
  end
end
