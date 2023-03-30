# This file is only used for assembling final releases and primarily
# is for specifying custom parameters for the Native NIF
import Config

config :host_core, HostCore.WasmCloud.Native,
  crate: :hostcore_wasmcloud_native,
  mode: if(Mix.env() == :dev, do: :debug, else: :release)
