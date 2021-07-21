use Mix.Config

# For production, NIFs should instead be loaded from predetermined directories
# This is for cross-compilation compatibility
config :host_core, HostCore.WasmCloud.Native,
  crate: :hostcore_wasmcloud_native,
  load_from: {:host_core, "priv/native/libhostcore_wasmcloud_native"},
  skip_compilation?: true

config :wasmex, Wasmex.Native,
  load_from: {:wasmex, "priv/native/libwasmex"},
  skip_compilation?: true
