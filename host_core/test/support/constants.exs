defmodule HostCoreTest.Constants do
  # Actor related constants
  @echo_key "MBCFOPM6JW2APJLXJD3Z5O4CN7CPYJ2B4FTKLJUR5YR5MITIU7HD3WD5"
  @echo_ociref "wasmcloud.azurecr.io/echo:0.2.0"
  @echo_ociref_updated "wasmcloud.azurecr.io/echo:0.2.1"
  @echo_path "test/fixtures/actors/echo_s.wasm"
  @kvcounter_key "MCFMFDWFHGKELOXPCNCDXKK5OFLHBVEWRAOXR5JSQUD2TOFRE3DFPM7E"
  @kvcounter_path "test/fixtures/actors/kvcounter_s.wasm"

  # Actor accessor methods
  def echo_key, do: @echo_key
  def echo_path, do: @echo_path
  def echo_ociref, do: @echo_ociref
  def echo_ociref_updated, do: @echo_ociref_updated
  def kvcounter_key, do: @kvcounter_key
  def kvcounter_path, do: @kvcounter_path

  # Provider related constants
  @httpserver_contract "wasmcloud:httpserver"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"

  # Provider accessor methods
  def httpserver_contract, do: @httpserver_contract
  def httpserver_key, do: @httpserver_key

  # Other related constants
  @default_link "default"

  # Other accessor methods
  def default_link, do: @default_link
end
