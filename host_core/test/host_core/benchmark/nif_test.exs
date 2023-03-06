defmodule HostCore.Benchmark.NifTest do
  # We'd rather not run this test asynchronously because it's a benchmark. We'll get better
  # results if this is the only test running at the time.
  use ExUnit.Case, async: false

  alias HostCore.WasmCloud.Native

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1]

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  describe "Benchmarking actor invocations" do
    setup :standard_setup

    test "load test with generate invocation bytes", %{
      :evt_watcher => _evt_watcher,
      :hconfig => config,
      :host_pid => pid
    } do
      on_exit(fn -> cleanup(pid, config) end)

      seed = config.cluster_seed
      host_id = config.host_key

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

      antiforgery_inv =
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
        |> IO.iodata_to_binary()

      test_config = %{
        "generate_invocation_bytes" => fn ->
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
        end,
        "validate_antiforgery" => fn ->
          Native.validate_antiforgery(
            antiforgery_inv,
            config.cluster_issuers
          )
        end,
        "host_config_lookup" => fn ->
          # This is a function that we've worried about blocking in concurrent requests before
          # and consists essentially just of an `:ets.lookup`
          HostCore.Vhost.VirtualHost.config(host_id)
        end
      }

      HostCore.Benchmark.Common.run_benchmark(test_config, 0, [50])

      assert true
    end
  end
end
