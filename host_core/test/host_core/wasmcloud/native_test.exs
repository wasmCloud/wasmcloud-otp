defmodule HostCore.WasmCloud.NativeTest do
  alias HostCore.WasmCloud.Native

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
    {:ok, path} = Native.get_oci_path(nil, @httpserver_oci, false, [])

    {:ok, par} = Native.ProviderArchive.from_path(path, "default")

    assert par.claims.public_key == @httpserver_key
    assert par.claims.issuer == @official_issuer
    assert par.claims.version == "0.14.10"

    stat =
      par.claims.public_key
      |> Native.par_cache_path(
        par.claims.revision,
        par.contract_id,
        "default"
      )
      |> File.stat!()

    assert stat.size > 1_000
    assert par.contract_id == @httpserver_contract
    assert par.vendor == @httpserver_vendor
  end

  test "generates seed keys" do
    {pub, seed} = Native.generate_key(:server)

    assert String.starts_with?(pub, "N")
    assert String.starts_with?(seed, "SN")
  end

  test "produces and validates invocation bytes" do
    {pub, seed} = Native.generate_key(:cluster)

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
      Native.generate_invocation_bytes(
        seed,
        "system",
        :provider,
        @httpserver_key,
        @httpserver_contract,
        @httpserver_link,
        "HandleRequest",
        req
      )

    res = inv |> IO.iodata_to_binary() |> Native.validate_antiforgery([pub])
    assert res == :ok

    decinv = Msgpax.unpack!(inv)

    # Rust struct is converted to map of strings
    assert decinv["host_id"] == pub
    assert decinv["origin"]["public_key"] == "system"
    assert decinv["target"]["public_key"] == @httpserver_key
  end

  test "validate antiforgery rejects bad issuer" do
    {_pub, seed} = Native.generate_key(:cluster)

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
      Native.generate_invocation_bytes(
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
      inv
      |> IO.iodata_to_binary()
      |> Native.validate_antiforgery([
        "CMYNAMEISKEVINIAMAMALICIOUSACTOR"
      ])

    assert res ==
             {:error, "Issuer of this invocation is not among the list of valid issuers"}
  end

  test "missing or zero revision is replaced with iat" do
    {:ok, bytes} = Native.get_oci_bytes(nil, @echo_oci, false, [])
    bytes = IO.iodata_to_binary(bytes)
    {:ok, claims} = Native.extract_claims(bytes)
    assert claims.public_key == @echo_key
    assert claims.issuer == @official_issuer
    assert claims.revision == 4

    {:ok, path} = Native.get_oci_path(nil, @httpserver_zero_revision_oci, false, [])

    {:ok, par} = Native.ProviderArchive.from_path(path, "default")

    assert par.claims.public_key == @httpserver_key
    assert par.claims.issuer == @official_issuer
    assert par.claims.revision == 1_631_292_694

    {:ok, bytes} = Native.get_oci_bytes(nil, @kvcounter_oci, false, [])
    bytes = IO.iodata_to_binary(bytes)
    {:ok, claims} = Native.extract_claims(bytes)
    assert claims.public_key == @kvcounter_key
    assert claims.issuer == @official_issuer
    assert claims.revision == 1_631_625_045
  end

  test "references containing capital letters are transparently converted to lowercase" do
    # e.g. "FoO.AzUrEcR.Io/oCiReF:0.1.2"
    spongebob_case_ref =
      String.graphemes(@echo_oci)
      |> Enum.map_every(2, fn c -> String.upcase(c) end)
      |> Enum.join("")

    {:ok, path} = Native.get_oci_path(nil, spongebob_case_ref, false, [])
    filename = path |> String.split("/") |> Enum.at(-1)
    assert filename |> String.graphemes() |> Enum.all?(fn c -> String.downcase(c) == c end)
  end
end
