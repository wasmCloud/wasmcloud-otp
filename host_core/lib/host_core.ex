defmodule HostCore do
  @moduledoc """
  `HostCore` Application.
  """
  require Logger
  use Application

  def start(_type, _args) do
    config = Vapor.load!(HostCore.ConfigPlan)
    config = post_process_config(config)

    children = mount_supervisor_tree(config)

    opts = [strategy: :one_for_one, name: HostCore.Supervisor]

    Logger.info(
      "Starting wasmCloud OTP Host Runtime v#{Application.spec(:host_core, :vsn) |> to_string()}"
    )

    Supervisor.start_link(children, opts)
  end

  defp mount_supervisor_tree(config) do
    [
      {Registry, keys: :unique, name: Registry.ProviderRegistry},
      {Registry, keys: :duplicate, name: Registry.ActorRegistry},
      {Registry,
       keys: :duplicate,
       name: Registry.EventMonitorRegistry,
       partitions: System.schedulers_online()},
      Supervisor.child_spec(
        {Gnat.ConnectionSupervisor, HostCore.Nats.control_connection_settings(config)},
        id: :control_connection_supervisor
      ),
      Supervisor.child_spec(
        {Gnat.ConnectionSupervisor, HostCore.Nats.rpc_connection_settings(config)},
        id: :rpc_connection_supervisor
      ),
      {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      {HostCore.Actors.ActorSupervisor,
       strategy: :one_for_one,
       allow_latest: config.allow_latest,
       allowed_insecure: config.allowed_insecure},
      # Handle lattice control interface requests
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :control_nats,
           module: HostCore.ControlInterface.Server,
           subscription_topics: [
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.registries.put"},
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.cmd.#{config.host_key}.*"},
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.ping.hosts"},
             %{
               topic: "wasmbus.ctl.#{config.lattice_prefix}.linkdefs.*",
               queue_group: "wasmbus.ctl.#{config.lattice_prefix}"
             },
             %{
               topic: "wasmbus.ctl.#{config.lattice_prefix}.get.*",
               queue_group: "wasmbus.ctl.#{config.lattice_prefix}"
             },
             %{
               topic: "wasmbus.ctl.#{config.lattice_prefix}.get.#{config.host_key}.inv"
             },
             %{topic: "wasmbus.ctl.#{config.lattice_prefix}.auction.>"}
           ]
         }},
        id: :latticectl_consumer_supervisor
      ),
      Supervisor.child_spec(
        {Gnat.ConsumerSupervisor,
         %{
           connection_name: :control_nats,
           module: HostCore.Jetstream.CacheLoader,
           subscription_topics: [
             %{topic: "#{config.cache_deliver_inbox}"}
           ]
         }},
        id: :cacheloader_consumer_supervisor
      ),
      {HostCore.Host, config},
      {HostCore.HeartbeatEmitter, config},
      {HostCore.Jetstream.Client, config}
    ]
  end

  defp post_process_config(config) do
    {host_key, host_seed} =
      if config.host_seed == nil do
        HostCore.WasmCloud.Native.generate_key(:server)
      else
        case HostCore.WasmCloud.Native.pk_from_seed(config.host_seed) do
          {:ok, pk} ->
            {pk, config.host_seed}

          {:error, _err} ->
            Logger.error(
              "Failed to obtain host public key from seed: #{config.host_seed}. Using new host key."
            )

            HostCore.WasmCloud.Native.generate_key(:server)
        end
      end

    config =
      config
      |> Map.put(:cluster_adhoc, false)
      |> Map.put(:cluster_key, "")
      |> Map.put(:host_key, host_key)
      |> Map.put(:host_seed, host_seed)

    s =
      Hashids.new(
        salt: "lc_deliver_inbox",
        min_len: 2
      )

    hid = Hashids.encode(s, Enum.random(1..4_294_967_295))
    config = Map.put(config, :cache_deliver_inbox, "_INBOX.#{hid}")

    if config.js_domain != nil && String.valid?(config.js_domain) &&
         String.length(config.js_domain) > 1 do
      Logger.info("Using JetStream domain: #{config.js_domain}")
    end

    {def_cluster_key, def_cluster_seed} = HostCore.WasmCloud.Native.generate_key(:cluster)

    chunk_config = %{
      "host" => config.rpc_host,
      "port" => "#{config.rpc_port}",
      "seed" => config.rpc_seed,
      "lattice" => config.lattice_prefix,
      "jwt" => config.rpc_jwt
    }

    chunk_config =
      if config.js_domain != nil do
        Map.put(config, "js_domain", config.js_domain)
      else
        chunk_config
      end

    case HostCore.WasmCloud.Native.set_chunking_connection_config(chunk_config) do
      :ok ->
        Logger.debug("Configured invocation chunking object store (NATS)")

      {:error, e} ->
        Logger.error("Failed to configure invocation chunking object store (NATS): #{inspect(e)}")
    end

    # we're generating the key, so we know this is going to work
    {:ok, issuer_key} = HostCore.WasmCloud.Native.pk_from_seed(def_cluster_seed)

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
        case HostCore.WasmCloud.Native.pk_from_seed(config.cluster_seed) do
          {:ok, pk} ->
            issuers = ensure_contains(config.cluster_issuers, pk)

            %{
              config
              | cluster_seed: config.cluster_seed,
                cluster_key: config.cluster_key,
                cluster_issuers: issuers,
                cluster_adhoc: false
            }

          {:error, err} ->
            Logger.error(
              "Invalid cluster seed '#{config.cluster_seed}': #{err}, falling back to ad hoc cluster key"
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

  defp write_config(config) do
    write_json(config, "./host_config.json")

    case System.user_home() do
      nil ->
        Logger.warn("Can't check for ~/.wash host config - no user home available")

      h ->
        write_json(config, Path.join([h, "/.wash/", "host_config.json"]))
    end
  end

  defp write_json(config, file) do
    with :ok <- File.mkdir_p(Path.dirname(file)) do
      case File.write(file, Jason.encode!(remove_extras(config))) do
        {:error, reason} -> Logger.error("Failed to write configuration file #{file}: #{reason}")
        :ok -> Logger.info("Wrote #{inspect(file)}")
      end
    else
      {:error, posix} ->
        Logger.error("Failed to create path to config file #{file}: #{posix}")
    end
  end

  defp remove_extras(config) do
    config
    |> Map.delete(:cluster_adhoc)
    |> Map.delete(:cache_deliver_inbox)
    |> Map.delete(:host_seed)
    |> Map.delete(:host_key)
  end

  defp ensure_contains(list, item) do
    if Enum.member?(list, item) do
      list
    else
      [item | list]
    end
  end
end
