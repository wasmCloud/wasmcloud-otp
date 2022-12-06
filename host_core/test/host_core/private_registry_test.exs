defmodule HostCore.PrivateRegistryTest do
  use ExUnit.Case, async: false

  alias HostCore.Vhost.VirtualHost

  import HostCoreTest.Common, only: [cleanup: 2, standard_setup: 1]

  setup :standard_setup

  @private_oci_registry_url HostCoreTest.Constants.private_oci_registry_url()
  @private_bindle_registry_url HostCoreTest.Constants.private_bindle_registry_url()

  @bad_credentials %{"tee" => "hee"}
  @missing_type_credentials %{"username" => "foo", "password" => "bar"}
  @missing_username_credentials %{"registryType" => "oci", "tee" => "hee"}
  @simple_credentials %{
    "registryType" => "oci",
    "username" => "oci-user",
    "password" => "oci-pass"
  }
  @simple_credentials_updated %{
    "registryType" => "oci",
    "username" => "oci-user-2",
    "password" => "oci-pass-2"
  }
  @bindle_credentials %{
    "registryType" => "bindle",
    "username" => "bindle-user-1",
    "password" => "bindle-pass-1"
  }

  @bad_credsmap %{@private_oci_registry_url => @bad_credentials}
  @missing_type_credsmap %{@private_oci_registry_url => @missing_type_credentials}
  @missing_username_credsmap %{@private_oci_registry_url => @missing_username_credentials}
  @simple_credsmap %{@private_oci_registry_url => @simple_credentials}
  @simple_credsmap_updated %{@private_oci_registry_url => @simple_credentials_updated}
  @bindle_credsmap %{@private_bindle_registry_url => @bindle_credentials}
  @oci_and_bindle_credsmap %{
    @private_oci_registry_url => @simple_credentials,
    @private_bindle_registry_url => @bindle_credentials
  }

  test "all creds are nil when no creds have been set", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    assert VirtualHost.get_creds(config.host_key, :oci, "foobar") == nil
  end

  test "malformed credentials are ignored", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @bad_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             nil
  end

  test "credentials without a type are ignored", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @missing_type_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             nil
  end

  test "credentials without a username/password/token are ignored", %{
    :hconfig => config,
    :host_pid => pid
  } do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @missing_username_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             nil
  end

  test "credentials can be looked up by server name", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @simple_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             @simple_credentials
  end

  test "credentials for unknown servers return nil", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @simple_credsmap)
    assert VirtualHost.get_creds(config.host_key, :oci, "foobar") == nil
  end

  test "credentials are segmented by registry type", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @simple_credsmap)

    assert VirtualHost.get_creds(
             config.host_key,
             :bindle,
             @private_oci_registry_url
           ) == nil
  end

  test "schemes are stripped from server names", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    schemes = ["bindle", "oci", "http", "https"]

    creds_map =
      Enum.reduce(schemes, %{}, fn scheme, acc ->
        server_url = scheme <> "://" <> scheme <> "-server"
        Map.put(acc, server_url, @simple_credentials)
      end)

    VirtualHost.set_credsmap(pid, creds_map)

    Enum.each(schemes, fn scheme ->
      assert VirtualHost.get_creds(config.host_key, :oci, scheme <> "-server") ==
               @simple_credentials
    end)
  end

  test "credentials can be looked up by OCI ref", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @simple_credsmap)
    oci_ref = @private_oci_registry_url <> "/echo:0.3.5"

    assert VirtualHost.get_creds(config.host_key, :oci, oci_ref) ==
             @simple_credentials
  end

  test "credentials can be looked up by bindle URI", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @bindle_credsmap)
    bindle_id = "mybindle@" <> @private_bindle_registry_url

    assert VirtualHost.get_creds(config.host_key, :bindle, bindle_id) ==
             @bindle_credentials
  end

  test "setting credentials is idempotent", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @simple_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             @simple_credentials

    VirtualHost.set_credsmap(pid, @simple_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             @simple_credentials
  end

  test "credentials can be updated", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @simple_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             @simple_credentials

    VirtualHost.set_credsmap(pid, @simple_credsmap_updated)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             @simple_credentials_updated
  end

  test "updates for one server do not affect another", %{:hconfig => config, :host_pid => pid} do
    on_exit(fn -> cleanup(pid, config) end)

    VirtualHost.set_credsmap(pid, @oci_and_bindle_credsmap)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             @simple_credentials

    assert VirtualHost.get_creds(
             config.host_key,
             :bindle,
             @private_bindle_registry_url
           ) == @bindle_credentials

    VirtualHost.set_credsmap(pid, @simple_credsmap_updated)

    assert VirtualHost.get_creds(config.host_key, :oci, @private_oci_registry_url) ==
             @simple_credentials_updated

    assert VirtualHost.get_creds(
             config.host_key,
             :bindle,
             @private_bindle_registry_url
           ) == @bindle_credentials
  end
end
