defmodule HostCore.ProvidersTest do
  use ExUnit.Case
  doctest HostCore.Providers
  @httpserver_path "priv/providers/httpserver"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"

  test "can load provider" do
    {:ok, pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        "default",
        "wasmcloud:httpserver"
      )

    assert HostCore.Providers.ProviderSupervisor.all_providers() |> length == 1
    HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, "default")
    assert HostCore.Providers.ProviderSupervisor.all_providers() |> length == 0
  end

  test "can enforce no duplicate providers" do
    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        "default",
        "wasmcloud:httpserver"
      )

    assert HostCore.Providers.ProviderSupervisor.all_providers() |> length == 1

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        "default",
        "wasmcloud:httpserver"
      )

    assert HostCore.Providers.ProviderSupervisor.all_providers() |> length == 1
    HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, "default")
    assert HostCore.Providers.ProviderSupervisor.all_providers() |> length == 0
  end
end
