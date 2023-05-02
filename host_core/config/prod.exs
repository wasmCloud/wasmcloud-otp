import Config

config :host_core, HostCore.WasmCloud.Native,
  mode: :release,
  skip_compilation?: true
