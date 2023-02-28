defmodule HostCore.Benchmark.Common do
  require Logger

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.Jetstream.Client, as: JetstreamClient
  alias HostCore.Vhost.VirtualHost
  alias HostCore.WasmCloud.Native

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
          time :: non_neg_integer()
        ) :: :ok
  # Run a benchmark with specified config, repeating for each parallel argument if it's a list
  def run_benchmark(test_config, num_actors, parallel \\ [1], warmup \\ 1, time \\ 5)
      when is_list(parallel) do
    parallel
    |> Enum.each(fn p -> run_benchmark(test_config, num_actors, p, warmup, time) end)

    :ok
  end

  def run_benchmark(test_config, num_actors, parallel, warmup, time)
      when is_number(parallel) do
    IO.puts("Benchmarking with #{num_actors} actors and #{parallel} parallel requests")
    pre_benchmark_run()

    Benchee.run(test_config,
      warmup: warmup,
      time: time,
      parallel: parallel
    )

    post_benchmark_run()
    :ok
  end
end
