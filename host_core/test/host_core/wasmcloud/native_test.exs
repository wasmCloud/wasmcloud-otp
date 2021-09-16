defmodule HostCore.WasmCloud.NativeTest do
  @httpserver_key HostCoreTest.Constants.httpserver_key()
  @httpserver_link HostCoreTest.Constants.default_link()
  @httpserver_contract HostCoreTest.Constants.httpserver_contract()
  @httpserver_oci HostCoreTest.Constants.httpserver_ociref()
  @official_issuer HostCoreTest.Constants.wasmcloud_issuer()
  @httpserver_vendor HostCoreTest.Constants.wasmcloud_vendor()

  use ExUnit.Case, async: false

  test "retrieves provider archive from OCI image" do
    {:ok, bytes} = HostCore.WasmCloud.Native.get_oci_bytes(@httpserver_oci, false, [])
    bytes = bytes |> IO.iodata_to_binary()

    {:ok, par} = HostCore.WasmCloud.Native.ProviderArchive.from_bytes(bytes)

    assert par.claims.public_key == @httpserver_key
    assert par.claims.issuer == @official_issuer
    assert par.claims.version == "0.14.3"

    target_bytes =
      case :os.type() do
        {:unix, :darwin} ->
          8_669_464

        {:unix, _linux} ->
          13_573_440

        {:win32, :nt} ->
          22_159_629
      end

    assert byte_size(par.target_bytes |> IO.iodata_to_binary()) == target_bytes
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
             {:error,
              "Validation of invocation/AF token failed: Issuer of this invocation is not among the list of valid issuers"}
  end
end
