defmodule HostCoreTest do
  use ExUnit.Case, async: false
  doctest HostCore

  @httpserver_path "priv/providers/httpserver"
  @echo_path "priv/actors/echo_s.wasm"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_link "default"
  @httpserver_contract "wasmcloud:httpserver"

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
    {:ok, bytes} = File.read("priv/actors/echo_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        @httpserver_link,
        @httpserver_contract
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
