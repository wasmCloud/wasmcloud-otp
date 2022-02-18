defmodule HostCore.ProvidersTest do
  use ExUnit.Case, async: false
  doctest HostCore.Providers

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_oci HostCoreTest.Constants.httpserver_ociref()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()

  test "can load provider from file", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, par} = HostCore.WasmCloud.Native.par_from_path(@httpserver_path, @httpserver_link)
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 1) ==
             httpserver_key

    HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )

    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end

  test "can load provider from OCI", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
        @httpserver_oci,
        "default"
      )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key
      )

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 1) ==
             @httpserver_key

    HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, @httpserver_link)

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        @httpserver_key
      )

    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end

  test "prevents starting duplicate local providers", %{:evt_watcher => evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    {:ok, par} = HostCore.WasmCloud.Native.par_from_path(@httpserver_path, @httpserver_link)
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 1) ==
             httpserver_key

    {:error, reason} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_file(
        @httpserver_path,
        @httpserver_link
      )

    assert reason == "Provider is already running on this host"

    provider_started_evts =
      HostCoreTest.EventWatcher.events_for_type(
        evt_watcher,
        "com.wasmcloud.lattice.provider_started"
      )
      |> Enum.count()

    assert provider_started_evts == 1

    assert elem(Enum.at(HostCore.Providers.ProviderSupervisor.all_providers(), 0), 1) ==
             httpserver_key

    HostCore.Providers.ProviderSupervisor.terminate_provider(httpserver_key, @httpserver_link)

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )

    assert HostCore.Providers.ProviderSupervisor.all_providers() == []
  end
end
