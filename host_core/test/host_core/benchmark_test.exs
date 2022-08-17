defmodule HostCore.BenchmarkTest do
  # Any test suite that relies on things like querying the actor count or the provider
  # count will need to be _synchronous_ tests so that other tests that rely on that same
  # information won't get bad/confusing results.
  use ExUnit.Case, async: false

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  test "load test with echo actor", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    num_actors = 10
    parallel = 1
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pids} = HostCore.Actors.ActorSupervisor.start_actor(bytes, "", num_actors)

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

    msg = %{
      body: inv |> IO.iodata_to_binary(),
      topic: "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_key}",
      reply_to: "_INBOX.thisisatest.notinterested"
    }

    IO.puts("Benchmarking with #{num_actors} actors and #{parallel} parallel requests")
    # very noisy debug logs during bench
    Logger.configure(level: :info)

    Benchee.run(
      %{
        "nats_echo_request" => fn ->
          HostCore.Nats.safe_req(:lattice_nats, msg.topic, inv, receive_timeout: 2_000)
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
