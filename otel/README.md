# wasmCloud OTP Host - OpenTelemetry Support
The wasmCloud host has support for [OpenTelemetry](https://opentelemetry.io) emissions that conform to the OpenTelemetry protocol. If you're interested, check out the [Elixir OpenTelemetry Getting Started](https://opentelemetry.io/docs/instrumentation/erlang/getting-started) guide.

Configuration can be done by developers modifying the `dev.exs` files in the config directory if they are running the wasmCloud host locally from source.

When deployed in production, you should use environment variables to configure the open telemetry exporter. For information on which environment variables are supported and their function, check [the OpenTelemetry specification](https://opentelemetry.io/docs/reference/specification/sdk-environment-variables/). (OTLP has its own [set of environment variables](https://opentelemetry.io/docs/reference/specification/protocol/exporter/))

We also _**strongly**_ recommend enabling wasmCloud's structured logging feature. When you do this, the `span_id` and `trace_id` fields will appear as top-level properties on the JSON payload emitted (when the log emission takes place within a trace context). This will let your log aggregation tool of choice facilitate correlation of logs with traces. You'll see these fields in the unstructured output as well, but it's easier to extract them from JSON than plain text.

## Example / Demo
If you want to play around with OpenTelemetry and some easily configured collectors and dashboards, there's a [compose.yaml](./compose.yaml) file that will start up **Grafana Tempo** for collecting traces and **Grafana** proper for exposing a dashboard that lets you look up traces.

You can either configure the endpoint via environment variables or uncomment the appropriate lines in the `dev.exs` files in the appropriate `config` folder. If you're using the compose file, you'll be able to browse to [localhost:5000](http://localhost:5000) to reach the Grafana home page. From there, just pick **Explore** and then **Tempo**. Paste a trace ID you capture either from looking at logs from the `docker logs otel-tempo-1` command or from sifting through the log output from the host.

## Common Environment Variables
For information on the Elixir-specific environment variables and how they're supposed to be used, check out the [opentelemetry_exporter](https://hexdocs.pm/opentelemetry_exporter/readme.html) docs.


While the entire suit of environment variables are available to you, the following will work with the docker compose file in this directory:

* `OTEL_TRACES_EXPORTER` - by default, tracing/trace exporting is disabled. To enable OTLP tracing, set the value of this environment variable to `otlp`
* `OTEL_EXPORTER_OTLP_ENDPOINT` - set to `http://localhost:55681` to use in the docker compose file
