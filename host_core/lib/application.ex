defmodule HostCore.Application do
  @moduledoc """
  The `HostCore` Application. This is the main entry point for the wasmCloud OTP host process supervision tree. At the
  application root level, the following supervisors will always be present:

  * ControlInterfaceTaskSupervisor - a task supervisor logically associated with control interface/operations tasks
  * HostTaskSupervisor - a task supervisor logically associated with performing operations in a virtual host
  * ProviderTaskSupervisor - a task supervisor logically associated with provider module operations
  * InvocationTaskSupervisor - a task supervisor logically associated with performing remote procedure calls and invoking Wasm components
  * ActorRpcSupervisor - the root owner of all actor RPC subscriptions, with one _queue_ subscription per public key
  * ProviderSupervisor - the root ovwner of all capability providers running inside this OTP application
  * ActorSupervisor - the root owner of all actors (webassembly components) running inside this OTP application
  * CallCounter - a per-actor call count incrementer that is used to ensure that the same actor is never invoked twice for RPC in a row (unless it's the only instance in the lattice)
  * LatticeRoot - the root owner of all lattice supervisors
  * VirtualHost - the first (and usually singleton) virtual host loaded into the application
  """
  require Logger
  use Application

  alias HostCore.Vhost.ConfigPlan
  alias HostCore.WasmCloud.Native

  @host_config_file "host_config.json"
  @extra_keys [
    :cluster_adhoc,
    :cache_deliver_inbox,
    :metadata_deliver_inbox,
    :host_seed,
    :enable_structured_logging,
    :structured_log_level,
    :host_key,
    :host_config
  ]

  def start(_type, _args) do
    create_ets_tables()

    config = Vapor.load!(ConfigPlan)
    config = post_process_config(config)

    OpentelemetryLoggerMetadata.setup()

    children = mount_supervisor_tree(config)

    opts = [strategy: :one_for_one, name: HostCore.ApplicationSupervisor]

    started = Supervisor.start_link(children, opts)

    if config.enable_structured_logging do
      :logger.set_primary_config(
        :logger.get_primary_config()
        |> Map.put(:level, config.structured_log_level)
      )

      :logger.add_handler(:structured_logger, :logger_std_h, %{
        formatter: {HostCore.StructuredLogger.FormatterJson, %{}},
        level: config.structured_log_level,
        config: %{
          type: :standard_error
        }
      })

      :logger.remove_handler(Logger)
    end

    Logger.info(
      "Started wasmCloud OTP Host Runtime",
      version: "#{to_string(Application.spec(:host_core, :vsn))}"
    )

    started
  end

  def host_count do
    Registry.count(Registry.HostRegistry)
  end

  # Returns [{host public key, <pid>, lattice_prefix}]
  @spec all_hosts() :: [{String.t(), pid(), String.t()}]
  def all_hosts do
    Registry.select(Registry.HostRegistry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
    ])
  end

  defp create_ets_tables do
    :ets.new(:vhost_config_table, [:named_table, :set, :public])
    :ets.new(:policy_table, [:named_table, :set, :public])
    :ets.new(:module_cache, [:named_table, :set, :public])
  end

  defp mount_supervisor_tree(config) do
    [
      {Registry, keys: :unique, name: Registry.LatticeSupervisorRegistry},
      {Registry, keys: :duplicate, name: Registry.ProviderRegistry},
      {Registry, keys: :unique, name: Registry.HostRegistry},
      {Registry, keys: :duplicate, name: Registry.ActorRegistry},
      {Registry, keys: :unique, name: Registry.ActorRpcSubscribers},
      {Registry,
       keys: :duplicate,
       name: Registry.EventMonitorRegistry,
       partitions: System.schedulers_online()},
      {Phoenix.PubSub, name: :hostcore_pubsub},
      {Task.Supervisor, name: ControlInterfaceTaskSupervisor},
      {Task.Supervisor, name: HostTaskSupervisor},
      {Task.Supervisor, name: ProviderTaskSupervisor},
      {Task.Supervisor, name: InvocationTaskSupervisor},
      {Task.Supervisor, name: RuntimeCallSupervisor},
      {HostCore.Actors.ActorRpcSupervisor, strategy: :one_for_one},
      {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      {HostCore.Actors.ActorSupervisor,
       strategy: :one_for_one,
       allow_latest: config.allow_latest,
       allowed_insecure: config.allowed_insecure,
       enable_actor_from_fs: config.enable_actor_from_fs},
      {HostCore.Actors.CallCounter, nil},
      {HostCore.Lattice.LatticeRoot, nil},
      {HostCore.Vhost.VirtualHost, config}
    ]
  end

  defp post_process_config(config) do
    {host_key, host_seed} =
      if config.host_seed == nil do
        Native.generate_key(:server)
      else
        case Native.pk_from_seed(config.host_seed) do
          {:ok, pk} ->
            {pk, config.host_seed}

          {:error, _err} ->
            Logger.error(
              "Failed to obtain host public key from seed: (#{config.host_seed}). Generating a new host key instead."
            )

            Native.generate_key(:server)
        end
      end

    host_config =
      if is_nil(config.host_config) do
        case System.user_home() do
          nil ->
            Logger.warn(
              "Could not determine user's home directory. Using current directory instead."
            )

            @host_config_file

          h ->
            Path.join([h, "/.wash/", @host_config_file])
        end
      else
        config.host_config
      end

    config =
      config
      |> Map.put(:cluster_adhoc, false)
      |> Map.put(:cluster_key, "")
      |> Map.put(:host_key, host_key)
      |> Map.put(:host_seed, host_seed)
      |> Map.put(:host_config, host_config)

    config = ensure_booleans(config)

    s =
      Hashids.new(
        salt: "lc_deliver_inbox",
        min_len: 2
      )

    s2 =
      Hashids.new(
        salt: "md_deliver_inbox",
        min_len: 2
      )

    hid = Hashids.encode(s, Enum.random(1..4_294_967_295))
    hid2 = Hashids.encode(s2, Enum.random(1..4_294_967_295))
    config = Map.put(config, :cache_deliver_inbox, "_INBOX.#{hid}")
    config = Map.put(config, :metadata_deliver_inbox, "INBOX.#{hid2}")

    if config.js_domain != nil && String.valid?(config.js_domain) &&
         String.length(config.js_domain) > 1 do
      Logger.info("Using JetStream domain: #{config.js_domain}", js_domain: "#{config.js_domain}")
    end

    {def_cluster_key, def_cluster_seed} = Native.generate_key(:cluster)

    chunk_config = %{
      "host" => config.rpc_host,
      "port" => "#{config.rpc_port}",
      "seed" => config.rpc_seed,
      "lattice" => config.lattice_prefix,
      "jwt" => config.rpc_jwt
    }

    chunk_config =
      if config.js_domain != nil do
        Map.put(chunk_config, "js_domain", config.js_domain)
      else
        chunk_config
      end

    case Native.set_chunking_connection_config(chunk_config) do
      :ok ->
        Logger.debug("Configured invocation chunking object store (NATS)")

      {:error, e} ->
        Logger.error(
          "Failed to configure invocation chunking object store (NATS): #{inspect(e)}. Any chunked invocations will fail."
        )
    end

    # we're generating the key, so we know this is going to work
    {:ok, issuer_key} = Native.pk_from_seed(def_cluster_seed)

    config =
      if config.cluster_seed == "" do
        %{
          config
          | cluster_seed: def_cluster_seed,
            cluster_key: def_cluster_key,
            cluster_issuers: [issuer_key],
            cluster_adhoc: true
        }
      else
        case Native.pk_from_seed(config.cluster_seed) do
          {:ok, pk} ->
            issuers = ensure_contains(config.cluster_issuers, pk)

            %{
              config
              | cluster_key: pk,
                cluster_issuers: issuers,
                cluster_adhoc: false
            }

          {:error, err} ->
            Logger.error(
              "Invalid cluster seed '#{config.cluster_seed}': #{err}, generating a new cluster seed instead."
            )

            %{
              config
              | cluster_seed: def_cluster_seed,
                cluster_key: def_cluster_key,
                cluster_issuers: [issuer_key],
                cluster_adhoc: true
            }
        end
      end

    write_config(config)

    config
  end

  defp ensure_booleans(config) do
    bool_keys = [:config_service_enabled, :ctl_tls, :rpc_tls, :enable_ipv6, :enable_actor_from_fs]

    Enum.reduce(bool_keys, config, fn key, config ->
      old = Map.get(config, key, nil)
      new = ConfigPlan.string_to_bool(old)
      Map.put(config, key, new)
    end)
  end

  defp write_config(config), do: write_json(config, config.host_config)

  defp write_json(config, file) do
    case file
         |> Path.dirname()
         |> File.mkdir_p() do
      :ok ->
        case File.write(file, Jason.encode!(remove_extras(config))) do
          {:error, reason} ->
            Logger.error("Failed to write configuration file #{file}: #{reason}")

          :ok ->
            Logger.info("Wrote configuration file #{file}")
        end

      {:error, posix} ->
        Logger.error("Failed to create path to config file #{file}: #{posix}")
    end
  end

  defp remove_extras(config), do: Map.drop(config, @extra_keys)

  defp ensure_contains(list, item) do
    if Enum.member?(list, item) do
      list
    else
      [item | list]
    end
  end
end
