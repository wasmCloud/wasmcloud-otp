defmodule HostCoreTest.Constants do
  # Actor related constants
  @echo_key "MBCFOPM6JW2APJLXJD3Z5O4CN7CPYJ2B4FTKLJUR5YR5MITIU7HD3WD5"
  @echo_ociref "wasmcloud.azurecr.io/echo:0.3.1"
  @echo_ociref_updated "wasmcloud.azurecr.io/echo:0.3.1-liveupdate"
  @echo_path "test/fixtures/actors/echo.wasm"
  @kvcounter_key "MCFMFDWFHGKELOXPCNCDXKK5OFLHBVEWRAOXR5JSQUD2TOFRE3DFPM7E"
  @kvcounter_path "test/fixtures/actors/kvcounter.wasm"
  @kvcounter_unpriv_key "MBW3UGAIONCX3RIDDUGDCQIRGBQQOWS643CVICQ5EZ7SWNQPZLZTSQKU"
  @kvcounter_unpriv_path "test/fixtures/actors/kvcounter_unpriv_s.wasm"
  @pinger_path "test/fixtures/actors/pinger_s.wasm"
  @pinger_key "MDCX6E7RPUXSX5TJUD34CALXJJKV46MWJ2BUJQGWDDR3IYRJIWNUQ5PN"

  # Provider related constants
  @httpserver_contract "wasmcloud:httpserver"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_ociref "wasmcloud.azurecr.io/httpserver:0.14.2"
  @httpserver_path "test/fixtures/providers/httpserver.par.gz"
  @keyvalue_contract "wasmcloud:keyvalue"
  @redis_key "VAZVC4RX54J2NVCMCW7BPCAHGGG5XZXDBXFUMDUXGESTMQEJLC3YVZWB"
  @redis_path "test/fixtures/providers/redis.par.gz"

  # Other related constants
  @default_link "default"
  @wasmcloud_issuer "ACOJJN6WUP4ODD75XEBKKTCCUJJCY5ZKQ56XVKYK4BEJWGVAOOQHZMCW"
  @wasmcloud_vendor "wasmCloud"

  # Actor accessor methods
  def echo_key, do: @echo_key
  def echo_path, do: @echo_path
  def echo_ociref, do: @echo_ociref
  def echo_ociref_updated, do: @echo_ociref_updated
  def kvcounter_key, do: @kvcounter_key
  def kvcounter_path, do: @kvcounter_path
  def kvcounter_unpriv_key, do: @kvcounter_unpriv_key
  def kvcounter_unpriv_path, do: @kvcounter_unpriv_path
  def pinger_path, do: @pinger_path
  def pinger_key, do: @pinger_key

  # Provider accessor methods
  def httpserver_contract, do: @httpserver_contract
  def httpserver_key, do: @httpserver_key
  def httpserver_ociref, do: @httpserver_ociref
  def httpserver_path, do: @httpserver_path
  def keyvalue_contract, do: @keyvalue_contract
  def redis_key, do: @redis_key
  def redis_path, do: @redis_path

  # Other accessor methods
  def default_link, do: @default_link
  def wasmcloud_issuer, do: @wasmcloud_issuer
  def wasmcloud_vendor, do: @wasmcloud_vendor
end
