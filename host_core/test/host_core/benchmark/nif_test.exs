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
          inv_id = UUID.uuid4()

          origin = %{
            public_key: actor,
            contract_id: "",
            link_name: ""
          }

          target =
            if target_type == :actor do
              %{
                public_key: target_key,
                contract_id: "",
                link_name: ""
              }
            else
              %{
                public_key: target_key,
                contract_id: namespace,
                link_name: link_name
              }
            end

          {:ok, {host_id, encoded_claims}} =
            Native.encoded_claims(
              seed,
              inv_id,
              "#{HostCore.WebAssembly.Imports.inv_url(target)}/#{operation}",
              HostCore.WebAssembly.Imports.inv_url(origin),
              payload,
              operation
            )

          inv =
            %{
              origin: origin,
              target: target,
              operation: operation,
              id: inv_id,
              encoded_claims: encoded_claims,
              host_id: host_id,
              content_length: 0
            }
            |> Msgpax.pack!()
            |> IO.iodata_to_binary()

          :ok
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
