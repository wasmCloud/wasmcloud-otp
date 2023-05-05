defmodule HostCore.E2E.ControlInterfaceTest do
  use ExUnit.Case, async: false

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.Linkdefs.Manager

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1]

  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  setup :standard_setup

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @redis_key HostCoreTest.Constants.redis_key()
  @redis_link HostCoreTest.Constants.default_link()
  @redis_contract HostCoreTest.Constants.keyvalue_contract()

  test "can get claims", %{:evt_watcher => _evt_watcher, :hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key, config.lattice_prefix)

    prefix = config.lattice_prefix
    topic = "wasmbus.ctl.#{prefix}.get.claims"

    Tracer.with_span "Make claims request", kind: :client do
      Logger.debug("Making claims request")

      {:ok, %{body: body}} =
        prefix
        |> HostCore.Nats.control_connection()
        |> HostCore.Nats.safe_req(topic, [], receive_timeout: 2_000)

      echo_claims =
        body
        |> Jason.decode!()
        |> Map.get("claims")
        |> Enum.find(fn claims -> Map.get(claims, "sub") == @echo_key end)

      assert Map.get(echo_claims, "sub") == @echo_key
    end
  end

  test "can get linkdefs", %{:evt_watcher => _evt_watcher, :hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    :ok =
      Manager.put_link_definition(
        config.lattice_prefix,
        @kvcounter_key,
        @redis_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )

    prefix = config.lattice_prefix
    topic = "wasmbus.ctl.#{prefix}.get.links"

    {:ok, %{body: body}} =
      prefix
      |> HostCore.Nats.control_connection()
      |> HostCore.Nats.safe_req(topic, [], receive_timeout: 2_000)

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
