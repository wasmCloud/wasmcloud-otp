defmodule HostCore.ProvidersTest do
  use ExUnit.Case, async: false
  doctest HostCore.Providers
  @httpserver_path "priv/providers/httpserver"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_link "default"
  @httpserver_contract "wasmcloud:httpserver"

  test "can load provider" do
    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        @httpserver_link,
        @httpserver_contract
      )

    Process.sleep(1000)
    assert HostCore.Providers.ProviderSupervisor.all_providers() == [
             {@httpserver_key, @httpserver_link, @httpserver_contract}
           ]

    HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, @httpserver_link)
    Process.sleep(500)
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end

  test "prevents starting duplicate local providers" do
    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        @httpserver_link,
        @httpserver_contract
      )
    Process.sleep(1000) # give provider a moment to load
    assert HostCore.Providers.ProviderSupervisor.all_providers() == [
             {@httpserver_key, @httpserver_link, @httpserver_contract}
           ]

    {:error, reason} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        @httpserver_link,
        @httpserver_contract
      )

    assert reason == "Provider is already running on this host"

    assert HostCore.Providers.ProviderSupervisor.all_providers() == [
             {@httpserver_key, @httpserver_link, @httpserver_contract}
           ]

    HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, @httpserver_link)
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end
end
