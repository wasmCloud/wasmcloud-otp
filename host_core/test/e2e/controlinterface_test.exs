defmodule HostCore.E2E.ControlInterfaceTest do
  use ExUnit.Case, async: false

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @redis_key HostCoreTest.Constants.redis_key()
  @redis_link HostCoreTest.Constants.default_link()
  @redis_contract HostCoreTest.Constants.keyvalue_contract()

  test "can get claims" do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

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
