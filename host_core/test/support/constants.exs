defmodule HostCoreTest.Constants do
  # Actor related constants
  @echo_key "MBCFOPM6JW2APJLXJD3Z5O4CN7CPYJ2B4FTKLJUR5YR5MITIU7HD3WD5"
  @echo_wasi_key "MCUXITMGLSPAFIMNHQVCC6DLXS6CHJN3NTER2NPP3F6QLR4QHR2SSPCW" # fixture key, not stored in OCI
  @echo_ociref "wasmcloud.azurecr.io/echo:0.3.1"
  @echo_ociref_updated "wasmcloud.azurecr.io/echo:0.3.1-liveupdate"
  @echo_path "test/fixtures/actors/echo.wasm"
  @echo_wasi_path "test/fixtures/actors/echo_wasi.wasm"
  @echo_unpriv_key "MCRACEYKJLCP7NLVMUTO2SCQ26JFL3Z4TBIXPXDE7KPBI2GEH5DA57L5"
  @echo_unpriv_path "test/fixtures/actors/echo_unpriv_s.wasm"

  @kvcounter_key "MCFMFDWFHGKELOXPCNCDXKK5OFLHBVEWRAOXR5JSQUD2TOFRE3DFPM7E"
  @kvcounter_ociref "wasmcloud.azurecr.io/kvcounter:0.3.0"
  @kvcounter_path "test/fixtures/actors/kvcounter.wasm"
  @kvcounter_unpriv_key "MBW3UGAIONCX3RIDDUGDCQIRGBQQOWS643CVICQ5EZ7SWNQPZLZTSQKU"
  @kvcounter_unpriv_path "test/fixtures/actors/kvcounter_unpriv_s.wasm"

  @pinger_path "test/fixtures/actors/pinger_s.wasm"
  @pinger_key "MDVMDDZP7QZH2T2447DZWX2GJ4563VTTKHQ26R6GNMDYMOUBR2EP3JFL"

  @policy_path "test/fixtures/actors/example_policy_s.wasm"
  @policy_key "MCX7HXCVATHJQRQLCCKV57R34V726FYRTDQL2QKPHXLYFWGOUE2LWRE3"

  # Provider related constants
  @httpserver_contract "wasmcloud:httpserver"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_ociref "wasmcloud.azurecr.io/httpserver:0.14.10"
  @httpserver_path "test/fixtures/providers/httpserver.par.gz"
  @keyvalue_contract "wasmcloud:keyvalue"
  @redis_key "VAZVC4RX54J2NVCMCW7BPCAHGGG5XZXDBXFUMDUXGESTMQEJLC3YVZWB"
  @redis_path "test/fixtures/providers/kvredis.par.gz"

  @nats_key "VADNMSIML2XGO2X4TPIONTIC55R2UUQGPPDZPAVSC2QD7E76CR77SPW7"
  @nats_ociref "wasmcloud.azurecr.io/nats_messaging:0.14.2"

  # Other related constants
  @default_link "default"
  @wasmcloud_issuer "ACOJJN6WUP4ODD75XEBKKTCCUJJCY5ZKQ56XVKYK4BEJWGVAOOQHZMCW"
  @wasmcloud_vendor "wasmCloud"

  # Actor accessor methods
  def echo_key, do: @echo_key
  def echo_wasi_key, do: @echo_wasi_key
  def echo_path, do: @echo_path
  def echo_wasi_path, do: @echo_wasi_path
  def echo_ociref, do: @echo_ociref
  def echo_ociref_updated, do: @echo_ociref_updated
  def echo_unpriv_key, do: @echo_unpriv_key
  def echo_unpriv_path, do: @echo_unpriv_path
  def kvcounter_key, do: @kvcounter_key
  def kvcounter_ociref, do: @kvcounter_ociref
  def kvcounter_path, do: @kvcounter_path
  def kvcounter_unpriv_key, do: @kvcounter_unpriv_key
  def kvcounter_unpriv_path, do: @kvcounter_unpriv_path
  def pinger_path, do: @pinger_path
  def pinger_key, do: @pinger_key
  def policy_path, do: @policy_path
  def policy_key, do: @policy_key

  # Provider accessor methods
  def httpserver_contract, do: @httpserver_contract
  def httpserver_key, do: @httpserver_key
  def httpserver_ociref, do: @httpserver_ociref
  def httpserver_path, do: @httpserver_path
  def keyvalue_contract, do: @keyvalue_contract
  def redis_key, do: @redis_key
  def redis_path, do: @redis_path
  def nats_key, do: @nats_key
  def nats_ociref, do: @nats_ociref

  # Other accessor methods
  def default_link, do: @default_link
  def wasmcloud_issuer, do: @wasmcloud_issuer
  def wasmcloud_vendor, do: @wasmcloud_vendor
end
