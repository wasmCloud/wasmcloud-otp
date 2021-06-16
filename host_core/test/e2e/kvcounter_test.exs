defmodule HostCore.E2E.KVCounterTest do
  use ExUnit.Case, async: false

  @kvcounter_key "MCFMFDWFHGKELOXPCNCDXKK5OFLHBVEWRAOXR5JSQUD2TOFRE3DFPM7E"
  @kvcounter_path "priv/actors/kvcounter_s.wasm"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_link "default"
  @httpserver_contract "wasmcloud:httpserver"
  @httpserver_path "priv/providers/httpserver"
  @redis_key "VAZVC4RX54J2NVCMCW7BPCAHGGG5XZXDBXFUMDUXGESTMQEJLC3YVZWB"
  @redis_link "default"
  @redis_contract "wasmcloud:keyvalue"
  @redis_path "priv/providers/wasmcloud-redis"

  test "kvcounter roundtrip" do
    {:ok, bytes} = File.read(@kvcounter_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        @httpserver_link,
        @httpserver_contract
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @redis_path,
        @redis_key,
        @redis_link,
        @redis_contract
      )

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @kvcounter_key)
      |> length

    assert actor_count == 1

    assert HostCore.Providers.ProviderSupervisor.all_providers() == [
             {@httpserver_key, @httpserver_link, @httpserver_contract},
             {@redis_key, @redis_link, @redis_contract}
           ]

    Process.sleep(1000)

    :ok =
      HostCore.LinkdefsManager.put_link_definition(
        @kvcounter_key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: "8081"}
      )

    :ok =
      HostCore.LinkdefsManager.put_link_definition(
        @kvcounter_key,
        @redis_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://0.0.0.0:6379"}
      )

    Process.sleep(1000)

    HTTPoison.start()
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")
    IO.inspect(resp)

    {:ok, body} = resp.body |> JSON.decode()
    incr_count = Map.get(body, "counter") + 1
    {:ok, resp} = HTTPoison.get("http://localhost:8081/foobar")
    assert resp.body == "{\"counter\":#{incr_count}}"

    Process.sleep(1000)

    HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, @httpserver_link)
    HostCore.Providers.ProviderSupervisor.terminate_provider(@redis_key, @redis_link)
  end
end
