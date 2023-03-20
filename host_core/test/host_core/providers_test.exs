defmodule HostCore.ProvidersTest do
  use ExUnit.Case, async: false

  alias HostCore.Providers.ProviderModule
  alias HostCore.Providers.ProviderSupervisor
  alias HostCore.WasmCloud.Native

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1]

  setup :standard_setup

  @httpserver_path HostCoreTest.Constants.httpserver_path()
  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_oci HostCoreTest.Constants.httpserver_ociref()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()

  test "can load provider from file", %{
    :evt_watcher => evt_watcher,
    :hconfig => config,
    :host_pid => pid
  } do
    on_exit(fn -> cleanup(pid, config) end)

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @httpserver_path,
        @httpserver_link,
        %{
          "is_testing" => "youbetcha"
        }
      )

    {:ok, par} = Native.par_from_path(@httpserver_path, @httpserver_link)
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    provs = ProviderSupervisor.all_providers(config.host_key)

    assert elem(Enum.at(provs, 0), 1) ==
             httpserver_key

    annotations = Enum.at(provs, 0) |> elem(0) |> ProviderModule.annotations()
    assert annotations == %{"is_testing" => "youbetcha"}

    ProviderSupervisor.terminate_provider(
      config.host_key,
      httpserver_key,
      @httpserver_link
    )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )

    if ProviderSupervisor.all_providers(config.host_key) != [] do
      :timer.sleep(1000)
    end

    assert ProviderSupervisor.all_providers(config.host_key) == []
  end

  test "can load provider from OCI", %{
    :evt_watcher => evt_watcher,
    :hconfig => config,
    :host_pid => pid
  } do
    on_exit(fn -> cleanup(pid, config) end)

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_oci(
        config.host_key,
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

    assert config.host_key
           |> ProviderSupervisor.all_providers()
           |> Enum.at(0)
           |> elem(1) ==
             @httpserver_key

    ProviderSupervisor.terminate_provider(
      config.host_key,
      @httpserver_key,
      @httpserver_link
    )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        @httpserver_key
      )

    if ProviderSupervisor.all_providers(config.host_key) != [] do
      :timer.sleep(1000)
    end

    assert ProviderSupervisor.all_providers(config.host_key) == []
  end

  test "prevents starting duplicate local providers", %{
    :evt_watcher => evt_watcher,
    :hconfig => config,
    :host_pid => pid
  } do
    on_exit(fn -> cleanup(pid, config) end)

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @httpserver_path,
        @httpserver_link
      )

    {:ok, par} = Native.par_from_path(@httpserver_path, @httpserver_link)
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    assert config.host_key
           |> ProviderSupervisor.all_providers()
           |> Enum.at(0)
           |> elem(1) ==
             httpserver_key

    {:error, reason} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @httpserver_path,
        @httpserver_link
      )

    assert reason == "Provider is already running on this host"

    provider_started_evts =
      evt_watcher
      |> HostCoreTest.EventWatcher.events_for_type("com.wasmcloud.lattice.provider_started")
      |> Enum.count()

    assert provider_started_evts == 1

    assert config.host_key |> ProviderSupervisor.all_providers() |> Enum.at(0) |> elem(1) ==
             httpserver_key

    ProviderSupervisor.terminate_provider(
      config.host_key,
      httpserver_key,
      @httpserver_link
    )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )

    if ProviderSupervisor.all_providers(config.host_key) != [] do
      :timer.sleep(1000)
    end

    assert ProviderSupervisor.all_providers(config.host_key) == []
  end

  test "emits health events on wasmbus.evt", %{
    :evt_watcher => evt_watcher,
    :hconfig => config,
    :host_pid => pid
  } do
    on_exit(fn -> cleanup(pid, config) end)

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_file(
        config.host_key,
        @httpserver_path,
        @httpserver_link,
        %{
          "is_testing" => "youbetcha"
        }
      )

    {:ok, par} = Native.par_from_path(@httpserver_path, @httpserver_link)
    httpserver_key = par.claims.public_key
    httpserver_contract = par.contract_id

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_start(
        evt_watcher,
        httpserver_contract,
        @httpserver_link,
        httpserver_key
      )

    :ok = HostCoreTest.EventWatcher.wait_for_event(evt_watcher, "health_check_passed")

    # wait for the health statys message which is sent every 30 seconds
    :ok =
      HostCoreTest.EventWatcher.wait_for_event(evt_watcher, "health_check_status", %{}, 1, 35_000)

    ProviderSupervisor.terminate_provider(
      config.host_key,
      httpserver_key,
      @httpserver_link
    )

    :ok =
      HostCoreTest.EventWatcher.wait_for_provider_stop(
        evt_watcher,
        @httpserver_link,
        httpserver_key
      )
  end
end
