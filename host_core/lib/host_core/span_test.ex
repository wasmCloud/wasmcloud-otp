defmodule HostCore.SpanTest do
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  this is just a function to illustrate how to work with otel trace propagation
  in elixir. This isn't invoked by any of the real production code. The main
  thing is to note the format of the propagation hashmap (trace context), which
  will be an elixir map that looks like this:

  %{
  "baggage" => "bob=keyless,alice=crypto",
  "traceparent" => "00-e1f0abf02136ac8e966e868668d310a4-5a915f9e4ac7dff2-01"
  }


  Elixir automatically knows how to reconstitute from this, but other languages
  might need to do some finagling. Note that elixir conforms to the RFC for
  trace context propagation
  """
  # def hello do
  #   injected =
  #     Tracer.with_span "handle_invocation" do
  #       IO.inspect(:opentelemetry.get_tracer())
  #       Logger.info("This is in the first span")
  #       Tracer.set_attribute("hello", "bob")
  #       OpenTelemetry.Baggage.set(%{"alice" => "crypto", "bob" => "keyless"})
  #       ctx = OpenTelemetry.Tracer.current_span_ctx()
  #       IO.inspect(OpenTelemetry.Span.trace_id(ctx))

  #       # tmap = :opentelemetry.get_text_map_extractor()
  #       # injector = :opentelemetry.get_text_map_injector()
  #       # extracted = :otel_propagator_text_map.extract(tmap, [])
  #       injected = :otel_propagator_text_map.inject([])

  #       IO.inspect(injected |> Enum.into(%{}))
  #       IO.inspect(injected)
  #     end

  #   Tracer.with_span "handle_invocation_elsewhere" do
  #     extracted = :otel_propagator_text_map.extract(injected)
  #     IO.inspect(extracted)
  #     ctx = OpenTelemetry.Tracer.current_span_ctx()
  #     IO.inspect(OpenTelemetry.Span.trace_id(ctx))

  #     Tracer.set_attribute("actor_id", "Mxxx")
  #     Tracer.set_attribute("operation", "HttpServer.HandleRequest")
  #     Logger.info("This log is inside the second span")

  #     Tracer.with_span "perform_invocation" do
  #       Tracer.set_attribute("operation", "KeyValue.Set")
  #       :timer.sleep(2000)
  #     end

  #     Tracer.with_span "perform_invocation" do
  #       Tracer.set_attribute("operation", "KeyValue.Get")
  #       :timer.sleep(2000)
  #     end
  #   end
  # end
end
