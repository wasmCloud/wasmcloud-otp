defmodule HostCore.Benchmark.Common do
  require Logger

  # Benchmarking common functions
  # Helper function to run before benchmark tests
  def pre_benchmark_run() do
    # Set level to info to reduce log noise
    Logger.configure(level: :info)
  end

  # Helper function to run after benchmark tests
  def post_benchmark_run() do
    # Return log level to debug
    Logger.configure(level: :debug)
  end

  @spec run_benchmark(
          test_config :: map(),
          num_actors :: non_neg_integer(),
          parallel :: list() | non_neg_integer(),
          warmup :: non_neg_integer(),
          time :: non_neg_integer(),
          profile_after :: boolean() | map() | atom()
        ) :: :ok
  # Run a benchmark with specified config, repeating for each parallel argument if it's a list
  def run_benchmark(
        test_config,
        num_actors,
        parallel \\ [1],
        warmup \\ 1,
        time \\ 5,
        profile_after \\ false
      )
      when is_list(parallel) do
    parallel
    |> Enum.each(fn p ->
      run_benchmark(test_config, num_actors, p, warmup, time, profile_after)
    end)

    :ok
  end

  def run_benchmark(test_config, num_actors, parallel, warmup, time, profile_after)
      when is_number(parallel) do
    IO.puts(
      "---\n- Benchmarking with #{num_actors} actors and #{parallel} parallel requests\n---"
    )

    pre_benchmark_run()

    Benchee.run(test_config,
      warmup: warmup,
      time: time,
      parallel: parallel,
      profile_after: profile_after
    )

    post_benchmark_run()
    :ok
  end

  # This function is leftover from some testing but nonetheless possibly useful
  # Simply call this function before a benchmark with a ms threshold, where if a NATS
  # message takes longer then information on the message is printed
  @spec gnat_latency_measure(threshold_ms :: non_neg_integer()) :: :ok
  defp gnat_latency_measure(threshold_ms) do
    metrics_function = fn event_name, measurements, event_meta, _config ->
      # Latency is in nanoseconds, ms * 1000 = ns
      if Map.get(measurements, :latency, 0) > threshold_ms * 1000 do
        IO.inspect([event_name, measurements, event_meta])
      end

      :ok
    end

    names = [
      [:gnat, :pub],
      [:gnat, :sub],
      [:gnat, :message_received],
      [:gnat, :request],
      [:gnat, :unsub]
    ]

    :telemetry.attach_many("my listener", names, metrics_function, %{})
    :ok
  end
end
