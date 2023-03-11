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

      # Encoded claims variables
      actor = "MCS4AAQ2NZZRTGKHGNBBFYH3RKQ7QLGOSI5TRRMRWFKMBD4KZFSL6EDF"
      target_type = :provider
      target_key = "VCPCNFTKMNMGVNK2VFJAAZ3263ND3E7PBCJKEJFX66EW4NEVP5N5MTOO"
      namespace = "wasmcloud:testing"
      link_name = "default"
      seed = "SNALQCCB7TXESX3WT2YGA466VJUTES3XQF6D75H546TPLS7RFZGNFAUNGM"
      payload = "oogabooga"
      operation = "WasmCloud.Testing"

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
        "encoded_claims" => fn ->
          # This function call includes the NIF call and all the data massaging for a true
          # comparison to generate_invocation_bytes
          HostCore.WebAssembly.Imports.actor_invocation(
            actor,
            target_key,
            target_key,
            namespace,
            link_name,
            operation,
            seed,
            payload
          )
        end,
        "host_config_lookup" => fn ->
          # This is a function that we've worried about blocking in concurrent requests before
          # and consists essentially just of an `:ets.lookup`
          HostCore.Vhost.VirtualHost.config(host_id)
        end
      }

      HostCore.Benchmark.Common.run_benchmark(test_config, 0, [10])

      assert true
    end
  end
end
