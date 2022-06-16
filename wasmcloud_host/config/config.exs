# This file is responsible for configuring your application
# and its dependencies with the aid of the .Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :opentelemetry, :resource, service: %{name: "wasmcloud"}

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none

# Configures the endpoint
config :wasmcloud_host, WasmcloudHostWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "t2L/jRnCFO9DrP/3gfnoS4n2Lypfq1+uuCz4LC5jV7K/ZPv9qq/ejh1L598mwhTE",
  render_errors: [view: WasmcloudHostWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: WasmcloudHost.PubSub,
  live_view: [signing_salt: "Jr0Bi5x0"]

# Subscription retention is a test-enabling tool. When enabled, a subscriber for
# an actor _will not unsubscribe_ after all instances of that actor have been
# removed from a host. This helps in testing because the constant churning of
# stopping, unsubscribing, starting, and re-subscribing in the middle of a test
# suite causes failure and race conditions on a large scale.
#
# tl;dr - leave subscription retention off at all times unless you're running
# tests.
config :host_core,
  retain_rpc_subscriptions: false

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :span_id, :trace_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Allow wasm uploads
config :mime, :types, %{
  "application/wasm" => ["wasm"],
  "application/tar" => ["par"],
  "application/gzip" => ["gz"]
}

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.12.18",
  default: [
    args: [
      "js/app.js",
      "--bundle",
      "--target=es2016",
      "--outdir=../priv/static/assets",
      "--inject:vendor/@coreui/coreui-pro/js/coreui.bundle.min.js",
      "--inject:vendor/phoenix/enable-topbar.js",
      "--inject:vendor/wasmcloud/js/extra.js",
      "--inject:vendor/wasmcloud/js/popovers.js",
      "--inject:vendor/wasmcloud/js/tooltips.js",
      "--external:/static/*"
    ],
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure Dart for scss support
config :dart_sass,
  version: "1.52.1"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
