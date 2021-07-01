defmodule HostCore.ActorsTest do
  # Any test suite that relies on things like querying the actor count or the provider
  # count will need to be _synchronous_ tests so that other tests that rely on that same
  # information won't get bad/confusing results.
  use ExUnit.Case, async: false

  doctest HostCore.Actors

  # Oddly enough, the key we have for the local .wasm for echo and the
  # key for the one in the OCI Azure registry are NOT the same. This is a classic
  # example of something that can really mess with a developer's day.
  @echo_key "MADQAFWOOOCZFDKYEYHC7AUQKDJTP32XUC5TDSMN4JLTDTU2WXBVPG4G"
  @echo_oci_key "MBCFOPM6JW2APJLXJD3Z5O4CN7CPYJ2B4FTKLJUR5YR5MITIU7HD3WD5"

  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @kvcounter_key "MCFMFDWFHGKELOXPCNCDXKK5OFLHBVEWRAOXR5JSQUD2TOFRE3DFPM7E"
  @httpserver_link "default"
  @httpserver_contract "wasmcloud:httpserver"
  @echo_oci_reference "wasmcloud.azurecr.io/echo:0.2.1"

  test "can load actors" do
    {:ok, bytes} = File.read("priv/actors/kvcounter_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    Process.sleep(1_000)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key)
      |> length

    assert actor_count == 5
    HostCore.Actors.ActorSupervisor.terminate_actor(@kvcounter_key, 5)
    Process.sleep(500)
    assert Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key) == nil
  end

  test "can invoke the echo actor" do
    {:ok, bytes} = File.read("priv/actors/echo_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    {pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

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
        "HandleRequest",
        req
      )

    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_key}"

    res =
      case Gnat.request(:lattice_nats, topic, inv, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    assert res != :fail
    HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1)

    ir = res |> Msgpax.unpack!()

    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["status"] == "OK"
    assert payload["statusCode"] == 200

    assert payload["body"] ==
             "{\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"HEYOOO\",\"headers\":{},\"body\":[104,101,108,108,111]}"
  end

  test "can invoke echo via OCI reference" do
    {:ok, pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_oci_reference)
    assert Process.alive?(pid)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_oci_key)
      |> length

    assert actor_count == 1

    {pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

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
        "HandleRequest",
        req
      )

    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{@echo_oci_key}"

    res =
      case Gnat.request(:lattice_nats, topic, inv, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    IO.inspect(res)
    assert res != :fail
    HostCore.Actors.ActorSupervisor.terminate_actor(@echo_oci_key, 1)

    ir = res |> Msgpax.unpack!()

    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["status"] == "OK"
    assert payload["statusCode"] == 200

    assert payload["body"] ==
             "{\"method\":\"GET\",\"path\":\"/\",\"query_string\":\"\",\"headers\":{},\"body\":[104,101,108,108,111]}"
  end

  test "can invoke via call alias" do
    {:ok, bytes} = File.read("priv/actors/ponger_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, bytes} = File.read("priv/actors/pinger_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    on_exit(fn ->
      # Ponger
      HostCore.Actors.ActorSupervisor.terminate_actor(
        "MBMOM2EZZICFYM4KATRMH2JUO5QWE3YWCHGFZVRQQ2SQI4I5BKWIGMBS",
        1
      )

      # Pinger
      HostCore.Actors.ActorSupervisor.terminate_actor(
        "MDCX6E7RPUXSX5TJUD34CALXJJKV46MWJ2BUJQGWDDR3IYRJIWNUQ5PN",
        1
      )
    end)

    {pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

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
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HandleRequest",
        req
      )

    pinger_key = "MDCX6E7RPUXSX5TJUD34CALXJJKV46MWJ2BUJQGWDDR3IYRJIWNUQ5PN"
    topic = "wasmbus.rpc.#{HostCore.Host.lattice_prefix()}.#{pinger_key}"

    res =
      case Gnat.request(:lattice_nats, topic, inv, receive_timeout: 2_000) do
        {:ok, %{body: body}} -> body
        {:error, :timeout} -> :fail
      end

    assert res != :fail

    ir = res |> Msgpax.unpack!()

    payload = ir["msg"] |> Msgpax.unpack!()

    assert payload["header"] == %{}
    assert payload["status"] == "OK"
    assert payload["statusCode"] == 200

    assert payload["body"] ==
             "{\"value\":53}"
  end
end
