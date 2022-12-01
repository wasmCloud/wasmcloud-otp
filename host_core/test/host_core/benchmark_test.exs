defmodule HostCore.BenchmarkTest do
  # We'd rather not run this test asynchronously because it's a benchmark. We'll get better
  # results if this is the only test running at the time.
  use ExUnit.Case, async: false

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1]

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  describe "Benchmarking actor invocations" do
    setup :standard_setup

    test "load test with echo actor", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      num_actors = 10
      parallel = 1
      {:ok, bytes} = File.read(@echo_path)

      {:ok, _pids} =
        HostCore.Actors.ActorSupervisor.start_actor(bytes, config.host_key, "", num_actors)

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

      msg = %{
        body: inv |> IO.iodata_to_binary(),
        topic: "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_key}",
        reply_to: "_INBOX.thisisatest.notinterested"
      }

      IO.puts("Benchmarking with #{num_actors} actors and #{parallel} parallel requests")
      # very noisy debug logs during bench
      Logger.configure(level: :info)

      Benchee.run(
        %{
          "nats_echo_request" => fn ->
            HostCore.Nats.safe_req(
              HostCore.Nats.rpc_connection(config.lattice_prefix),
              msg.topic,
              inv,
              receive_timeout: 2_000
            )
          end,
          "direct_echo_request" => fn ->
            HostCore.Actors.ActorRpcServer.request(msg)
          end
        },
        warmup: 1,
        time: 5,
        parallel: parallel
      )

      # turning debug logs back on
      Logger.configure(level: :debug)

      assert true
    end
  end
end
