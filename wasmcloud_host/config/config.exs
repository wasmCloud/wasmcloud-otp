# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

# Configures the endpoint
config :wasmcloud_host, WasmcloudHostWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "t2L/jRnCFO9DrP/3gfnoS4n2Lypfq1+uuCz4LC5jV7K/ZPv9qq/ejh1L598mwhTE",
  render_errors: [view: WasmcloudHostWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: WasmcloudHost.PubSub,
  live_view: [signing_salt: "Jr0Bi5x0"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
