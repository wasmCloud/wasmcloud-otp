defmodule HostCore.E2E.KVCounterTest do
  use ExUnit.Case, async: false

  require Logger

  @kvcounter_key "MCFMFDWFHGKELOXPCNCDXKK5OFLHBVEWRAOXR5JSQUD2TOFRE3DFPM7E"
  @kvcounter_path "test/fixtures/actors/kvcounter_s.wasm"

  @kvcounter_unpriv_key "MAVJWHLVXBCJI3BPJDMHB3MFZMGFASOJ3CYDNSHNZJDVGW4B4E7SIYFG"
  @kvcounter_unpriv_path "test/fixtures/actors/kvcounter_unpriv_s.wasm"

  @httpserver_link "default"
  @httpserver_path "test/fixtures/providers/httpserver.par.gz"
  @redis_link "default"
  @redis_path "test/fixtures/providers/redis.par.gz"

  test "kvcounter roundtrip" do
    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@kvcounter_key, 1) end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    par = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    {:ok, bytes} = File.read(@redis_path)
    par = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    redis_key = par.claims.public_key
    redis_contract = par.contract_id

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(redis_key, @redis_link)
    end)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key)
      |> length

    assert actor_count == 1

    ap = HostCore.Providers.ProviderSupervisor.all_providers()
    assert elem(Enum.at(ap, 0), 0) == httpserver_key
    assert elem(Enum.at(ap, 1), 0) == redis_key

    Process.sleep(2000)

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        httpserver_contract,
        @httpserver_link,
        httpserver_key,
        %{PORT: "8081"}
      )

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        redis_contract,
        @redis_link,
        redis_key,
        %{URL: "redis://0.0.0.0:6379"}
      )

    Process.sleep(1000)

    HTTPoison.start()
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")

    # Retrieve current count, assert next request increments by 1
    {:ok, body} = resp.body |> JSON.decode()
    incr_count = Map.get(body, "counter") + 1
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")
    assert resp.body == "{\"counter\":#{incr_count}}"
  end

  test "kvcounter unprivileged access denied" do
    {:ok, bytes} = File.read(@kvcounter_unpriv_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@kvcounter_key, 1) end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    par = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @redis_path,
        @redis_link
      )

    {:ok, bytes} = File.read(@redis_path)
    par = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    redis_key = par.claims.public_key
    redis_contract = par.contract_id

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(redis_key, @redis_link)
    end)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_unpriv_key)
      |> length

    assert actor_count == 1

    ap = HostCore.Providers.ProviderSupervisor.all_providers()
    assert elem(Enum.at(ap, 0), 0) == httpserver_key
    assert elem(Enum.at(ap, 1), 0) == redis_key

    Process.sleep(2000)

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        httpserver_contract,
        @httpserver_link,
        httpserver_key,
        %{PORT: "8081"}
      )

    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_unpriv_key,
        redis_contract,
        @redis_link,
        redis_key,
        %{URL: "redis://0.0.0.0:6379"}
      )

    Process.sleep(1000)

    HTTPoison.start()
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")
    IO.inspect(resp)

    assert resp.body == "Guest call failed: Host error: Invocation not authorized\n"
    assert resp.status_code == 500
  end
end
