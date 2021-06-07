defmodule HostCore.WasmCloud.NativeTest do
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_link "default"
  @httpserver_contract "wasmcloud:httpserver"

  use ExUnit.Case

  test "generates seed keys" do
    {pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

    assert String.starts_with?(pub, "N")
    assert String.starts_with?(seed, "SN")
  end

  test "produces invocation bytes" do
    {pub, seed} = HostCore.WasmCloud.Native.generate_key(:server)

    req = %{
      body: "hello",
      header: %{},
      path: "/",
      method: "GET"
    } |> Msgpax.pack!() |> IO.iodata_to_binary()

    inv = HostCore.WasmCloud.Native.generate_invocation_bytes(
      seed,
      "system",
      :provider,
      @httpserver_key,
      @httpserver_contract,
      @httpserver_link,
      "HandleRequest",
      req)

    decinv = inv |> Msgpax.unpack!()

    assert decinv["host_id"] == pub
    # the 0/1 here are for how Rust enums get serialized.
    assert decinv["origin"][0] == "system"
    assert decinv["target"][1]["id"] == @httpserver_key
  end
end
