defmodule HostCoreTest do
  use ExUnit.Case, async: false
  doctest HostCore

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @httpserver_path "test/fixtures/providers/httpserver.par.gz"
  @echo_path "test/fixtures/actors/echo_s.wasm"
  @echo_key "MADQAFWOOOCZFDKYEYHC7AUQKDJTP32XUC5TDSMN4JLTDTU2WXBVPG4G"
  @httpserver_link "default"

  test "greets the world" do
    assert HostCore.hello() == :world
  end

  test "Host stores intrinsic values" do
    # should never appear
    System.put_env("hostcore.osfamily", "fakeroo")
    System.put_env("HOST_TESTING", "42")
    labels = HostCore.Host.host_labels()

    family_target =
      case :os.type() do
        {:unix, _linux} -> "unix"
        {:unix, :darwin} -> "unix"
        {:win32, :nt} -> "windows"
      end

    assert family_target == labels["hostcore.osfamily"]
    # HOST_ prefix removed.
    assert "42" == labels["testing"]
  end

  test "Host purges actors and providers", %{:evt_watcher => evt_watcher} do
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    :ok =
      HostCoreTest.EventWatcher.wait_for_actor_start(
        evt_watcher,
        @echo_key
      )

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    HostCore.Host.purge()

    :ok = HostCoreTest.EventWatcher.wait_for_actor_stop(evt_watcher, @echo_key)

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )

    actor_count =
      HostCore.Actors.ActorSupervisor.all_actors()
      |> Map.keys()
      |> length

    assert actor_count == 0
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end
end
