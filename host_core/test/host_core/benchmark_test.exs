defmodule HostCore.BenchmarkTest do
  # We'd rather not run this test asynchronously because it's a benchmark. We'll get better
  # results if this is the only test running at the time.
  use ExUnit.Case, async: false

  alias HostCore.Actors.ActorRpcServer
  alias HostCore.Actors.ActorSupervisor
  alias HostCore.Providers.ProviderSupervisor
  alias HostCore.Linkdefs.Manager
  alias HostCore.WasmCloud.Native

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1, request_http: 2]

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_path HostCoreTest.Constants.httpserver_path()

  describe "Benchmarking actor invocations" do
    setup :standard_setup

    test "load test with echo actor", %{
      :evt_watcher => evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      num_actors = 10
      parallel = 1
      {:ok, bytes} = File.read(@echo_path)

      {:ok, _pids} = ActorSupervisor.start_actor(bytes, config.host_key, "", num_actors)

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

      msg = %{
        body: IO.iodata_to_binary(inv),
        topic: "wasmbus.rpc.#{config.lattice_prefix}.#{@echo_key}",
        reply_to: "_INBOX.thisisatest.notinterested"
      }

      :ok =
        Manager.put_link_definition(
          config.lattice_prefix,
          @echo_key,
          @httpserver_contract,
          @httpserver_link,
          @httpserver_key,
          %{PORT: "8084"}
        )

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

      IO.puts("Benchmarking with #{num_actors} actors and #{parallel} parallel requests")
      # very noisy debug logs during bench
      Logger.configure(level: :info)

      {:ok, _okay} = HTTPoison.start()

      Benchee.run(
        %{
          # "nats_echo_request" => fn ->
          #   config.lattice_prefix
          #   |> HostCore.Nats.rpc_connection()
          #   |> HostCore.Nats.safe_req(msg.topic, inv, receive_timeout: 2_000)
          # end,
          # "direct_echo_request" => fn ->
          #   ActorRpcServer.request(msg)
          # end,
          "http_echo_request" => fn ->
            {:ok, _resp} = request_http("http://localhost:8084/foobar", 1)
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
