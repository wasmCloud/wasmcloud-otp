import Config

# config :opentelemetry, :processors,
#   otel_batch_processor: %{
#     exporter: {:opentelemetry_exporter, %{endpoints: [{:http, 'localhost', 55681, []}]}}
#   }

config :logger, :console, level: :debug

config :host_core,
  retain_rpc_subscriptions: true

# config :opentelemetry, :processors,
#   otel_batch_processor: %{
#     exporter: {:otel_exporter_stdout, []}
#   }
