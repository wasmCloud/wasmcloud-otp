defmodule HostCore.Host do
  @moduledoc false
  use GenServer, restart: :transient
  alias HostCore.CloudEvent
  require Logger

  # To set this value in a release, edit the `env.sh` file that is generated
  # by a mix release.

  defmodule State do
    @moduledoc false
    defstruct [:host_key, :lattice_prefix, :labels, :friendly_name, :supplemental_config]
  end

  @doc """
  Starts the host server
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  NATS is used for all lattice communications, which includes communication between actors and capability providers,
  whether those capability providers are local or remote.

  The following is an outline of the important subject spaces required for providers, the host, and RPC listeners. All
  subscriptions are not in a queue group unless otherwise specified.

  * `wasmbus.rpc.{prefix}.{public_key}` - Send invocations to an actor Invocation->InvocationResponse
  * `wasmbus.rpc.{prefix}.{public_key}.{link_name}` - Send invocations (from actors only) to Providers  Invocation->InvocationResponse
  * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.put` - Publish link definition (e.g. bind to an actor)
  * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.get` - Query all link defs for this provider. (queue subscribed)
  * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.del` - Remove a link def.
  * `wasmbus.rpc.{prefix}.claims.put` - Publish discovered claims
  * `wasmbus.rpc.{prefix}.claims.get` - Query all claims (queue subscribed by hosts)
  * `wasmbus.rpc.{prefix}.refmaps.put` - Publish a reference map, e.g. OCI ref -> PK, call alias -> PK
  * `wasmbus.rpc.{prefix}.refmaps.get` - Query all reference maps (queue subscribed by hosts)
  """
  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    configure_ets()

    :ets.insert(:config_table, {:config, opts})

    friendly_name = HostCore.Namegen.generate()

    Logger.info("Host #{opts.host_key} (#{friendly_name}) started.")
    Logger.info("Valid cluster signers: #{opts.cluster_issuers}")

    if opts.cluster_adhoc do
      warning = """
      WARNING. You are using an ad hoc generated cluster seed.
      For any other host or CLI tool to communicate with this host,
      you MUST copy the following seed key and use it as the value
      of the WASMCLOUD_CLUSTER_SEED environment variable:

      #{opts.cluster_seed}

      You must also ensure the following cluster signer is in the list of valid
      signers for any new host you start:

      #{opts.cluster_issuers |> Enum.at(0)}

      """

      Logger.warn(warning)
    end

    labels =
      get_env_host_labels()
      |> Map.merge(HostCore.WasmCloud.Native.detect_core_host_labels())

    publish_host_started(labels, friendly_name)

    state = %State{
      host_key: opts.host_key,
      lattice_prefix: opts.lattice_prefix,
      friendly_name: friendly_name,
      labels: labels
    }

    if config_service_enabled?(opts) do
      {:ok, state, {:continue, :load_supp_config}}
    else
      {:ok, state}
    end
  end

  # truthy
  defp config_service_enabled?(opts) do
    String.upcase(opts.config_service_enabled) in [
      "TRUE",
      "YES",
      "Y",
      "YOU BETCHA",
      "YUPPERS",
      "TOTES",
      "ENABLED"
    ]
  end

  @impl true
  def handle_continue(:load_supp_config, state) do
    topic = "wasmbus.cfg.#{state.lattice_prefix}"
    Logger.debug("Requesting supplemental host configuration via topic '#{topic}'")

    state =
      with {:ok, supp_config} <-
             HostCore.ConfigServiceClient.request_configuration(
               state.labels,
               topic
             ) do
        %State{state | supplemental_config: supp_config}
      else
        {:error, e} ->
          Logger.error("Failed to obtain supplemental configuration: #{inspect(e)}")
          state
      end

    {:noreply, state, {:continue, :process_supp_config}}
  end

  @impl true
  def handle_continue(:process_supp_config, %State{supplemental_config: nil} = state) do
    {:noreply, state}
  end

  # NOTE - we do this work in a handle continue because we need the registry credentials
  # to be a part of this process's state prior to attempting to start the components in the
  # supp config's prestarts
  @impl true
  def handle_continue(:process_supp_config, %State{supplemental_config: sc} = state) do
    aps = Map.get(sc, "autoStartProviders", [])
    as = Map.get(sc, "autoStartActors", [])

    Logger.info(
      "Processing supplemental configuration: #{length(aps)} providers, #{length(as)} actors"
    )

    Task.start(fn ->
      aps
      |> Enum.each(fn prov ->
        if !Map.has_key?(prov, "imageReference") || !Map.has_key?(prov, "linkName") do
          Logger.error("Not enough information on auto-start provider configuration. Bypassing.")
        else
          if String.starts_with?(prov["imageReference"], "bindle://") do
            HostCore.Providers.ProviderSupervisor.start_provider_from_bindle(
              prov["imageReference"],
              prov["linkName"]
            )
          else
            HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
              prov["imageReference"],
              prov["linkName"]
            )
          end
        end
      end)

      as
      |> Enum.each(fn actor ->
        if String.starts_with?(actor, "bindle://") do
          HostCore.Actors.ActorSupervisor.start_actor_from_bindle(actor)
        else
          HostCore.Actors.ActorSupervisor.start_actor_from_oci(actor)
        end
      end)
    end)

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Host termination requested: #{inspect(reason)}")
    publish_host_stopped(state.labels)
    :timer.sleep(300)
  end

  defp get_env_host_labels() do
    keys =
      System.get_env() |> Map.keys() |> Enum.filter(fn k -> String.starts_with?(k, "HOST_") end)

    Map.new(keys, fn k ->
      {String.slice(k, 5..999) |> String.downcase(), System.get_env(k, "")}
    end)
  end

  @impl true
  def handle_call({:get_creds, ref}, _from, state) do
    nref = ref |> normalize_prefix()

    if state.supplemental_config == nil do
      {:reply, nil, state}
    else
      res =
        if String.contains?(nref, "@") do
          # extract server from bindle://invoice@server, look for
          # credentials in map equal to bindle://server
          server = nref |> extract_bindle_server()

          if server != nil do
            Map.get(state.supplemental_config, "registryCredentials", %{})
            |> Enum.find(fn {k, _v} ->
              k == "bindle://#{server}"
            end)
          else
            nil
          end
        else
          Map.get(state.supplemental_config, "registryCredentials", %{})
          |> Enum.find(fn {k, _v} ->
            String.starts_with?(nref, k)
          end)
        end

      {:reply,
       if res != nil do
         elem(res, 1)
       else
         nil
       end, state}
    end
  end

  @impl true
  def handle_call(:get_labels, _from, state) do
    {:reply, state.labels, state}
  end

  @impl true
  def handle_call(:get_friendly, _from, state) do
    {:reply, state.friendly_name, state}
  end

  @impl true
  def handle_info({:do_stop, _timeout_ms}, state) do
    # TODO: incorporate timeout into graceful shutdown

    purge()
    publish_host_stopped(state.labels)

    # Give a little bit of time for the event to get sent before shutting down
    :timer.sleep(300)

    :init.stop()
    {:noreply, state}
  end

  defp publish_host_stopped(labels) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        labels: labels
      }
      |> CloudEvent.new("host_stopped")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  defp publish_host_started(labels, friendly_name) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        labels: labels,
        friendly_name: friendly_name
      }
      |> CloudEvent.new("host_started")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  defp configure_ets() do
    :ets.new(:provider_table, [:named_table, :set, :public])
    :ets.new(:linkdef_table, [:named_table, :set, :public])
    :ets.new(:claims_table, [:named_table, :set, :public])
    :ets.new(:refmap_table, [:named_table, :set, :public])
    :ets.new(:callalias_table, [:named_table, :set, :public])
    :ets.new(:config_table, [:named_table, :set, :public])
  end

  def lattice_prefix() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:lattice_prefix]
      _ -> "default"
    end
  end

  def host_key() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:host_key]
      _ -> ""
    end
  end

  def get_creds(ref) do
    GenServer.call(__MODULE__, {:get_creds, ref})
  end

  def friendly_name() do
    GenServer.call(__MODULE__, :get_friendly)
  end

  def seed() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:host_seed]
      _ -> ""
    end
  end

  def cluster_seed() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:cluster_seed]
      _ -> ""
    end
  end

  def provider_shutdown_delay() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:provider_delay]
      _ -> 300
    end
  end

  def rpc_timeout() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:rpc_timeout]
      _ -> 2_000
    end
  end

  def cluster_issuers() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:cluster_issuers]
      _ -> []
    end
  end

  def host_labels() do
    GenServer.call(__MODULE__, :get_labels)
  end

  def purge() do
    Logger.info("Host purge requested")
    HostCore.Actors.ActorSupervisor.terminate_all()
    HostCore.Providers.ProviderSupervisor.terminate_all()
  end

  def generate_hostinfo_for(provider_key, link_name, instance_id, config_json) do
    {url, jwt, seed, tls} =
      case :ets.lookup(:config_table, :config) do
        [config: config_map] ->
          {"#{config_map[:prov_rpc_host]}:#{config_map[:prov_rpc_port]}",
           config_map[:prov_rpc_jwt], config_map[:prov_rpc_seed], config_map[:prov_rpc_tls]}

        _ ->
          {"127.0.0.1:4222", "", ""}
      end

    lds =
      HostCore.Linkdefs.Manager.get_link_definitions()
      |> Enum.filter(fn %{link_name: ln, provider_id: prov} ->
        ln == link_name && prov == provider_key
      end)

    %{
      host_id: host_key(),
      lattice_rpc_prefix: lattice_prefix(),
      link_name: link_name,
      lattice_rpc_user_jwt: jwt,
      lattice_rpc_user_seed: seed,
      lattice_rpc_url: url,
      lattice_rpc_tls: tls,
      # for backwards compatibility
      env_values: %{},
      instance_id: instance_id,
      provider_key: provider_key,
      link_definitions: lds,
      config_json: config_json,
      cluster_issuers: cluster_issuers(),
      invocation_seed: cluster_seed()
    }
    |> Jason.encode!()
  end

  defp normalize_prefix("bindle://" <> _str = s) do
    s
  end

  defp normalize_prefix("oci://" <> _str = s) do
    s
  end

  defp normalize_prefix(str) do
    "oci://#{str}"
  end

  defp extract_bindle_server("bindle://" <> trailing) do
    trailing |> String.split("@", trim: true) |> Enum.at(-1)
  end

  defp extract_bindle_server(other), do: other
end
