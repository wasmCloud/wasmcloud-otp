defmodule HostCoreTest do
  use ExUnit.Case
  doctest HostCore

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
end
