import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  level: :debug,
  metadata: [:span_id, :trace_id]

# Uncomment one of the below items ONLY if you're not using environment variables to
# configure the otel exporter AND you're not using wasmcloud_host (e.g. you're running
# headless from host_core).
#
# config :opentelemetry, :processors,
#   otel_batch_processor: %{
#     exporter: {:otel_exporter_stdout, []}
#   }

# config :opentelemetry, :processors,
#   otel_batch_processor: %{
#     exporter: {:opentelemetry_exporter, %{endpoints: [{:http, 'localhost', 55681, []}]}}
#   }
