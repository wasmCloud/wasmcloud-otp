defmodule HostCoreTest.Common do
  require Logger

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.Jetstream.Client, as: JetstreamClient
  alias HostCore.Vhost.VirtualHost
  alias HostCore.WasmCloud.Native

  def actor_count(host_key, counter_key) do
    host_key
    |> ActorSupervisor.all_actors()
    |> Map.get(counter_key)
    |> length
  end

  def request_http(url, retries) when retries > 0 do
    case HTTPoison.get(url) do
      {:ok, resp} ->
        {:ok, resp}

      _ ->
        Logger.debug("HTTP request failed, retrying in 1000ms, remaining retries #{retries}")
        :timer.sleep(1000)
        request_http(url, retries - 1)
    end
  end

  def request_http(_url, 0) do
    # IO.puts("YO! YOUR HTTP LIBRARY MAY BE MESSED UP, CURL #{url}")
    # :timer.sleep(60000)
    {:error, "Connection refused after retries"}
  end

  def sudo_make_me_a_host(lattice_id) when is_binary(lattice_id) do
    config = default_vhost_config()
    config = %{config | lattice_prefix: lattice_id}

    VirtualHost.start_link(config)
  end

  def standard_setup(_context) do
    lattice_id = UUID.uuid4()
    {:ok, host_pid} = HostCoreTest.Common.sudo_make_me_a_host(lattice_id)

    {:ok, evt_watcher} = GenServer.start_link(HostCoreTest.EventWatcher, lattice_id)

    [
      evt_watcher: evt_watcher,
      host_pid: host_pid,
      hconfig: VirtualHost.config(host_pid)
    ]
  end

  def cleanup(pid, config) do
    VirtualHost.stop(pid, 300)
    purge_topic = "$JS.API.STREAM.DELETE.LATTICECACHE_#{config.lattice_prefix}"

    case config.lattice_prefix
         |> HostCore.Nats.control_connection()
         |> HostCore.Nats.safe_req(
           purge_topic,
           []
         ) do
      {:ok, %{body: _body}} ->
        Logger.debug("Purged NATS stream for lattice cache")

      {:error, :timeout} ->
        Logger.error("Failed to purge NATS stream for lattice cache within timeout")

      {:error, :no_responders} ->
        Logger.error("Failed to purge NATS stream for lattice cache - no responders")
    end

    case JetstreamClient.delete_kv_bucket(config.lattice_prefix, nil) do
      {:ok, %{body: _body}} ->
        Logger.debug("Deleted metadata cache for lattice")

      {:error, :timeout} ->
        Logger.error("Failed to delete metadata cache bucket within timeout")

      {:error, :no_responders} ->
        Logger.error("No responders for request to delete metadata cache bucket")
    end
  end

  def default_vhost_config do
    {pk, seed} = Native.generate_key(:server)
    {ck, cseed} = Native.generate_key(:cluster)

    s =
      Hashids.new(
        salt: "lc_deliver_inbox",
        min_len: 2
      )

    hid = Hashids.encode(s, Enum.random(1..4_294_967_295))
    hid2 = Hashids.encode(s, Enum.random(1..4_294_967_295))

    %{
      lattice_prefix: "default",
      cache_deliver_inbox: "_INBOX.#{hid}",
      metadata_deliver_inbox: "INBOX.#{hid2}",
      host_seed: seed,
      cluster_key: ck,
      cluster_adhoc: false,
      host_key: pk,
      rpc_host: "127.0.0.1",
      rpc_port: 4222,
      rpc_seed: "",
      rpc_timeout_ms: 2000,
      rpc_jwt: "",
      rpc_tls: false,
      prov_rpc_host: "127.0.0.1",
      prov_rpc_port: 4222,
      prov_rpc_seed: "",
      prov_rpc_tls: false,
      prov_rpc_jwt: "",
      ctl_host: "127.0.0.1",
      ctl_seed: "",
      ctl_jwt: "",
      ctl_port: 4222,
      ctl_tls: false,
      ctl_topic_prefix: "wasmbus.ctl",
      cluster_seed: cseed,
      cluster_issuers: [ck],
      provider_delay: 300,
      allow_latest: false,
      allowed_insecure: [],
      js_domain: nil,
      config_service_enabled: false,
      enable_structured_logging: false,
      structure_log_level: :info,
      enable_ipv6: false,
      enable_actor_from_fs: true,
      policy_topic: nil,
      policy_changes_topic: nil,
      policy_timeout_ms: 1_000
    }
  end

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

    Benchee.run(test_config,
      warmup: warmup,
      time: time,
      parallel: parallel
    )

    :ok
  end
end
