# This file is only used for assembling final releases and primarily
# is for specifying custom parameters for the Native host_core NIF
import Config

import_config "prod.secret.exs"
import_config "prod.exs"

config :host_core, HostCore.WasmCloud.Native,
  crate: :host_core_native,
  mode: if(Mix.env() == :dev, do: :debug, else: :release),
  skip_compilation?: if(Mix.env() == :release_prod, do: true, else: false),
  load_from: {:host_core, "priv/built/libhostcore_wasmcloud_native"}
