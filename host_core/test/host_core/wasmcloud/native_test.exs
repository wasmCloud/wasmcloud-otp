defmodule HostCore.WasmCloud.NativeTest do
  @kvcounter_oci HostCoreTest.Constants.kvcounter_ociref()
  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @echo_oci HostCoreTest.Constants.echo_ociref()
  @echo_key HostCoreTest.Constants.echo_key()
  @httpserver_zero_revision_oci "wasmcloud.azurecr.io/httpserver:0.14.0"

  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_oci HostCoreTest.Constants.httpserver_ociref()
  @official_issuer HostCoreTest.Constants.wasmcloud_issuer()
  @httpserver_vendor HostCoreTest.Constants.wasmcloud_vendor()

  use ExUnit.Case, async: false

  test "retrieves provider archive from OCI image" do
    {:ok, path} = HostCore.WasmCloud.Native.get_oci_path(nil, @httpserver_oci, false, [])

    {:ok, par} = HostCore.WasmCloud.Native.ProviderArchive.from_path(path, "default")

    assert par.claims.public_key == @httpserver_key
    assert par.claims.issuer == @official_issuer
    assert par.claims.version == "0.14.10"

    stat =
      File.stat!(
        HostCore.WasmCloud.Native.par_cache_path(
          par.claims.public_key,
          par.claims.revision,
          par.contract_id,
          "default"
        )
      )

    assert stat.size > 1_000
    assert par.contract_id == @httpserver_contract
    assert par.vendor == @httpserver_vendor
  end

  test "generates seed keys" do
    {pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

    assert String.starts_with?(pub, "N")
    assert String.starts_with?(seed, "SN")
  end

  test "produces and validates invocation bytes" do
    {pub, seed} = HostCore.WasmCloud.Native.generate_key(:cluster)

    req =
      %{
        body: "hello",
        header: %{},
        path: "/",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    inv =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HandleRequest",
        req
      )

    res = HostCore.WasmCloud.Native.validate_antiforgery(inv |> IO.iodata_to_binary(), [pub])
    assert res == :ok

    decinv = inv |> Msgpax.unpack!()

    # Rust struct is converted to map of strings
    assert decinv["host_id"] == pub
    assert decinv["origin"]["public_key"] == "system"
    assert decinv["target"]["public_key"] == @httpserver_key
  end

  test "validate antiforgery rejects bad issuer" do
    {_pub, seed} = HostCore.WasmCloud.Native.generate_key(:cluster)

    req =
      %{
        body: "hello",
        header: %{},
        path: "/",
        method: "GET"
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    inv =
      HostCore.WasmCloud.Native.generate_invocation_bytes(
        seed,
        "system",
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HandleRequest",
        req
      )

    res =
      HostCore.WasmCloud.Native.validate_antiforgery(inv |> IO.iodata_to_binary(), [
        "CMYNAMEISKEVINIAMAMALICIOUSACTOR"
      ])

    assert res ==
             {:error, "Issuer of this invocation is not among the list of valid issuers"}
  end

  test "missing or zero revision is replaced with iat" do
    {:ok, bytes} = HostCore.WasmCloud.Native.get_oci_bytes(nil, @echo_oci, false, [])
    bytes = bytes |> IO.iodata_to_binary()
    {:ok, claims} = HostCore.WasmCloud.Native.extract_claims(bytes)
    assert claims.public_key == @echo_key
    assert claims.issuer == @official_issuer
    assert claims.revision == 4

    {:ok, path} =
      HostCore.WasmCloud.Native.get_oci_path(nil, @httpserver_zero_revision_oci, false, [])

    {:ok, par} = HostCore.WasmCloud.Native.ProviderArchive.from_path(path, "default")

    assert par.claims.public_key == @httpserver_key
    assert par.claims.issuer == @official_issuer
    assert par.claims.revision == 1_631_292_694

    {:ok, bytes} = HostCore.WasmCloud.Native.get_oci_bytes(nil, @kvcounter_oci, false, [])
    bytes = bytes |> IO.iodata_to_binary()
    {:ok, claims} = HostCore.WasmCloud.Native.extract_claims(bytes)
    assert claims.public_key == @kvcounter_key
    assert claims.issuer == @official_issuer
    assert claims.revision == 1_631_625_045
  end
end
