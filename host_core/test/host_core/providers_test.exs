defmodule HostCore.ProvidersTest do
  use ExUnit.Case, async: false
  doctest HostCore.Providers
  @httpserver_path "test/fixtures/providers/httpserver.par.gz"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_link "default"
  @httpserver_oci "wasmcloud.azurecr.io/httpserver:0.13.1"

  test "can load provider from file" do
    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key

    # Ensure provider is cleaned up regardless of test errors
    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    Process.sleep(1000)

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 0) ==
             httpserver_key

    HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)

    # give provider a moment to stop
    Process.sleep(1000)
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end

  test "can load provider from OCI" do
    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
        @httpserver_oci,
        "default"
      )

    # Ensure provider is cleaned up regardless of test errors
    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, @httpserver_link)
    end)

    Process.sleep(1000)

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 0) ==
             @httpserver_key

    HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, @httpserver_link)

    # give provider a moment to stop
    Process.sleep(1000)
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end

  test "prevents starting duplicate local providers" do
    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, bytes} = File.read(@httpserver_path)
    {:ok, par} = HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary())
    httpserver_key = par.claims.public_key

    # Ensure provider is cleaned up regardless of test errors
    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)
    end)

    # give provider a moment to load
    Process.sleep(1000)

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 0) ==
             httpserver_key

    {:error, reason} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    assert reason == "Provider is already running on this host"

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 0) ==
             httpserver_key

    HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)

    # give provider a moment to stop
    Process.sleep(1000)
    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end
end
