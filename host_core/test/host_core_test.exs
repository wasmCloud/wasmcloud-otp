defmodule HostCoreTest do
  use ExUnit.Case, async: false
  doctest HostCore

  @httpserver_path "test/fixtures/providers/httpserver.par.gz"
  @echo_path "test/fixtures/actors/echo_s.wasm"
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

  test "Host purges actors and providers" do
    {:ok, bytes} = File.read("test/fixtures/actors/echo_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    Process.sleep(1_000)
    HostCore.Host.purge()
    Process.sleep(2_000)

    actor_count =
      HostCore.Actors.ActorSupervisor.all_actors()
      |> Map.keys()
      |> length

    assert actor_count == 0
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end
end
