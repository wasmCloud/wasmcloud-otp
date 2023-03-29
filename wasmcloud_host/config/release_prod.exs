# This file is only used for assembling final releases and primarily
# is for specifying custom parameters for the Native host_core NIF
import Config

import_config "prod.exs"

config :host_core, HostCore.WasmCloud.Native,
  crate: :hostcore_wasmcloud_native,
  mode: if(Mix.env() == :dev, do: :debug, else: :release)
