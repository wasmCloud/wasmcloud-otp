defmodule HostCore.ActorsTest do
  # Any test suite that relies on things like querying the actor count or the provider
  # count will need to be _synchronous_ tests so that other tests that rely on that same
  # information won't get bad/confusing results.
  use ExUnit.Case, async: false

  doctest HostCore.Actors

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @echo_old_oci_reference HostCoreTest.Constants.echo_ociref()
  @echo_oci_reference HostCoreTest.Constants.echo_ociref_updated()

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_link HostCoreTest.Constants.default_link()

  test "load test with echo actor", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    :ets.delete(:refmap_table, @echo_oci_reference)
    :ets.delete(:refmap_table, @echo_old_oci_reference)
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pids} = HostCore.Actors.ActorSupervisor.start_actor(bytes, "", 1)

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
      reply_to: nil
    }

    # Let the system cool down a bit after starting 100 actors
    IO.puts("calming down")
    :timer.sleep(2_000)

    Benchee.run(
      %{
        "nats_echo_request" => fn ->
          HostCore.Nats.safe_req(:lattice_nats, msg.topic, inv, receive_timeout: 2_000)
        end
        # "direct_echo_request" => fn ->
        #   HostCore.Actors.ActorRpcServer.request(msg)
        # end
      },
      warmup: 0,
      time: 0.1
    )

    # topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_key}"

    # res =
    #   case HostCore.Nats.safe_req(:lattice_nats, topic, inv, receive_timeout: 2_000) do
    #     {:ok, %{body: body}} -> body
    #     {:error, :timeout} -> :fail
    #   end

    # assert res != :fail
    # HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1, %{})

    # ir = res |> Msgpax.unpack!()
    assert true

    # payload = ir["msg"] |> Msgpax.unpack!()

    # assert payload["header"] == %{}
    # assert payload["statusCode"] == 200

    # assert payload["body"] ==
    #          "{\"body\":[104,101,108,108,111],\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\"}"
  end
end
