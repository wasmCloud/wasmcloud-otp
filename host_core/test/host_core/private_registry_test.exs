defmodule HostCore.PrivateRegistryTest do
  use ExUnit.Case, async: false

  setup do
    HostCore.Host.clear_credsmap()
  end

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

  test "all creds are nil when no creds have been set" do
    assert HostCore.Host.get_creds(:oci, "foobar") == nil
  end

  test "malformed credentials are ignored" do
    HostCore.Host.set_credsmap(@bad_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == nil
  end

  test "credentials without a type are ignored" do
    HostCore.Host.set_credsmap(@missing_type_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == nil
  end

  test "credentials without a username/password/token are ignored" do
    HostCore.Host.set_credsmap(@missing_username_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == nil
  end

  test "credentials can be looked up by server name" do
    HostCore.Host.set_credsmap(@simple_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == @simple_credentials
  end

  test "credentials for unknown servers return nil" do
    HostCore.Host.set_credsmap(@simple_credsmap)
    assert HostCore.Host.get_creds(:oci, "foobar") == nil
  end

  test "credentials are segmented by registry type" do
    HostCore.Host.set_credsmap(@simple_credsmap)
    assert HostCore.Host.get_creds(:bindle, @private_oci_registry_url) == nil
  end

  test "schemes are stripped from server names" do
    schemes = ["bindle", "oci", "http", "https"]

    creds_map =
      schemes
      |> Enum.reduce(%{}, fn scheme, acc ->
        serverUrl = scheme <> "://" <> scheme <> "-server"
        Map.put(acc, serverUrl, @simple_credentials)
      end)

    HostCore.Host.set_credsmap(creds_map)

    schemes
    |> Enum.each(fn scheme ->
      assert HostCore.Host.get_creds(:oci, scheme <> "-server") == @simple_credentials
    end)
  end

  test "credentials can be looked up by OCI ref" do
    HostCore.Host.set_credsmap(@simple_credsmap)
    oci_ref = @private_oci_registry_url <> "/echo:0.3.5"
    assert HostCore.Host.get_creds(:oci, oci_ref) == @simple_credentials
  end

  test "credentials can be looked up by bindle URI" do
    HostCore.Host.set_credsmap(@bindle_credsmap)
    bindle_id = "mybindle@" <> @private_bindle_registry_url
    assert HostCore.Host.get_creds(:bindle, bindle_id) == @bindle_credentials
  end

  test "setting credentials is idempotent" do
    HostCore.Host.set_credsmap(@simple_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == @simple_credentials
    HostCore.Host.set_credsmap(@simple_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == @simple_credentials
  end

  test "credentials can be updated" do
    HostCore.Host.set_credsmap(@simple_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == @simple_credentials
    HostCore.Host.set_credsmap(@simple_credsmap_updated)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == @simple_credentials_updated
  end

  test "updates for one server do not affect another" do
    HostCore.Host.set_credsmap(@oci_and_bindle_credsmap)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == @simple_credentials
    assert HostCore.Host.get_creds(:bindle, @private_bindle_registry_url) == @bindle_credentials
    HostCore.Host.set_credsmap(@simple_credsmap_updated)
    assert HostCore.Host.get_creds(:oci, @private_oci_registry_url) == @simple_credentials_updated
    assert HostCore.Host.get_creds(:bindle, @private_bindle_registry_url) == @bindle_credentials
  end
end
