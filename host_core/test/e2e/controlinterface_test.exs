defmodule HostCore.E2E.ControlInterfaceTest do
  use ExUnit.Case, async: false

  @echo_key "MADQAFWOOOCZFDKYEYHC7AUQKDJTP32XUC5TDSMN4JLTDTU2WXBVPG4G"

  @kvcounter_key "MCFMFDWFHGKELOXPCNCDXKK5OFLHBVEWRAOXR5JSQUD2TOFRE3DFPM7E"
  @redis_key "VAZVC4RX54J2NVCMCW7BPCAHGGG5XZXDBXFUMDUXGESTMQEJLC3YVZWB"
  @redis_link "default"
  @redis_contract "wasmcloud:keyvalue"

  test "can get claims" do
    {:ok, bytes} = File.read("test/fixtures/actors/echo_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1) end)

    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.ctl.#{prefix}.get.claims"

    {:ok, %{body: body}} = Gnat.request(:control_nats, topic, [], receive_timeout: 2_000)

    echo_claims =
      body
      |> Jason.decode!()
      |> Map.get("claims")
      |> Enum.find(fn claims -> Map.get(claims, "sub") == @echo_key end)

    assert Map.get(echo_claims, "sub") == @echo_key
  end

  test "can get linkdefs" do
    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        @redis_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://0.0.0.0:6379"}
      )

    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.ctl.#{prefix}.get.links"

    {:ok, %{body: body}} = Gnat.request(:control_nats, topic, [], receive_timeout: 2_000)

    kvcounter_redis_link =
      body
      |> Jason.decode!()
      |> Map.get("links")
      |> Enum.find(fn linkdef ->
        Map.get(linkdef, "actor_id") == @kvcounter_key &&
          Map.get(linkdef, "provider_id") == @redis_key
      end)

    assert Map.get(kvcounter_redis_link, "actor_id") == @kvcounter_key
    assert Map.get(kvcounter_redis_link, "provider_id") == @redis_key
    assert Map.get(kvcounter_redis_link, "contract_id") == @redis_contract
    assert Map.get(kvcounter_redis_link, "link_name") == @redis_link
  end
end
