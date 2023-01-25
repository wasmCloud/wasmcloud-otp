defmodule HostCore.Vhost.VirtualHost do
  @moduledoc """
  The _Virtual Host_ is a unit of containment for resources such as actors and capability providers. It is launched immediately
  upon application startup using the configuration supplied by the configuration plan pipeline and the setting of appropriate defaults.
  Each virtual host also subscribes to the following topic patterns:

  * {ctl_prefix}.{lattice_prefix}.cmd.{host_key}.*
  * {ctl_prefix}.{lattice_prefix}.get.{host_key}.inv

  Lattices are managed in the `HostCore.Lattice.LatticeSupervisor`, with one being started for each lattice obtained through configuration
  """

  use GenServer, restart: :transient

  require Logger

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.CloudEvent
  alias HostCore.Lattice.LatticeRoot
  alias HostCore.Linkdefs.Manager
  alias HostCore.Providers.ProviderSupervisor
  alias HostCore.Vhost.Configuration
  alias HostCore.WasmCloud.Native
  alias Timex.Format.Duration.Formatters.Humanized

  defmodule State do
    @moduledoc """
    The state of the virtual host is a record containing the following fields:

    * `config` - the configuration for the virtual host
    * `friendly_name` - a friendly name for the virtual host
    * `labels` - a map of labels for the virtual host
    * `start_time` - the time at which the virtual host was started
    * `supplemental_config` - a map of supplemental configuration for the virtual host
    """

    @type t :: %State{
            config: Configuration.t(),
            friendly_name: String.t(),
            labels: Map.t(),
            start_time: non_neg_integer(),
            supplemental_config: Map.t() | nil
          }
    defstruct [:config, :friendly_name, :start_time, :labels, :supplemental_config]
  end

  @doc """
  Starts the virtual host
  """
  @spec start_link(config :: Configuration.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(config) do
    GenServer.start_link(__MODULE__, config,
      name: via_tuple(config.host_key, config.lattice_prefix)
    )
  end

  @impl true
  @spec init(config :: HostCore.Vhost.Configuration.t()) ::
          {:ok, HostCore.Vhost.VirtualHost.State.t(),
           {:continue, :load_supp_config | :publish_started}}
  def init(config) do
    Process.flag(:trap_exit, true)

    case LatticeRoot.start_lattice(config) do
      {:ok, _pid} ->
        Logger.info("Lattice supervisor #{config.lattice_prefix} started.")

      {:error, e} ->
        Logger.error("Lattice supervisor #{config.lattice_prefix} failed to start: #{inspect(e)}")
    end

    friendly_name = HostCore.Namegen.generate()

    Logger.info("Virtual Host #{config.host_key} (#{friendly_name}) started.")
    Logger.info("Virtual Host Issuer Public key: #{config.cluster_key}")
    Logger.info("Valid cluster signers for host: #{config.cluster_issuers}")

    if config.cluster_adhoc do
      warning = """
      WARNING. You are using an ad hoc generated cluster seed.
      For any other host or CLI tool to communicate with this host,
      you MUST copy the following seed key and use it as the value
      of the WASMCLOUD_CLUSTER_SEED environment variable:

      #{config.cluster_seed}

      You must also ensure the following cluster signer is in the list of valid
      signers for any new host you start:

      #{Enum.at(config.cluster_issuers, 0)}

      """

      Logger.warn(warning)
    end

    labels = Map.merge(get_env_host_labels(), Native.detect_core_host_labels())

    Gnat.ConsumerSupervisor.start_link(%{
      connection_name: HostCore.Nats.control_connection(config.lattice_prefix),
      module: HostCore.ControlInterface.HostServer,
      subscription_topics: [
        %{
          topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.cmd.#{config.host_key}.*"
        },
        %{
          topic: "#{config.ctl_topic_prefix}.#{config.lattice_prefix}.get.#{config.host_key}.inv"
        }
      ]
    })

    HostCore.Vhost.Heartbeats.start_link(self(), config.host_key)

    {wclock, _} = :erlang.statistics(:wall_clock)

    Logger.metadata(host_id: config.host_key, lattice_prefix: config.lattice_prefix)

    :ets.insert(:vhost_config_table, {config.host_key, config})

    state = %State{
      config: Map.put(config, :labels, labels),
      friendly_name: friendly_name,
      start_time: wclock,
      labels: labels,
      supplemental_config: nil
    }

    if config.config_service_enabled do
      {:ok, state, {:continue, :load_supp_config}}
    else
      {:ok, state, {:continue, :publish_started}}
    end
  end

  @impl true
  def handle_continue(:load_supp_config, state) do
    topic = "wasmbus.cfg.#{state.config.lattice_prefix}"
    Logger.debug("Requesting supplemental host configuration via topic '#{topic}'.")

    case HostCore.ConfigServiceClient.request_configuration(
           state.config.lattice_prefix,
           state.labels,
           topic
         ) do
      {:ok, supp_config} ->
        {:noreply, %State{state | supplemental_config: supp_config},
         {:continue, :process_supp_config}}

      {:error, e} ->
        Logger.warn("Failed to obtain supplemental configuration: #{inspect(e)}.")
        {:noreply, state, {:continue, :publish_started}}
    end
  end

  def handle_continue(:process_supp_config, %State{supplemental_config: sc} = state) do
    autostart_providers = Map.get(sc, "autoStartProviders", [])
    autostart_actors = Map.get(sc, "autoStartActors", [])

    Logger.info(
      "Processing supplemental configuration: #{length(autostart_providers)} providers, #{length(autostart_actors)} actors"
    )

    Task.start(fn ->
      Enum.each(autostart_providers, fn prov -> start_autostart_provider(prov, state) end)
      Enum.each(autostart_actors, fn actor -> start_autostart_actor(actor, state) end)
    end)

    {:noreply, state, {:continue, :publish_started}}
  end

  def handle_continue(:publish_started, state) do
    publish_host_started(state)
    {:noreply, state}
  end

  def via_tuple(host_id, lattice_prefix) do
    {:via, Registry, {Registry.HostRegistry, host_id, lattice_prefix}}
  end

  @spec lookup(host_id :: String.t()) :: :error | {:ok, {pid(), String.t()}}
  def lookup(host_id) do
    case Registry.lookup(Registry.HostRegistry, host_id) do
      [] ->
        Logger.warn("Failed to look up host ID #{host_id}")
        :error

      [{pid, value}] ->
        {:ok, {pid, value}}
    end
  end

  # Obtains -registry- credentials
  def get_creds(host_id, type, ref) do
    case lookup(host_id) do
      :error ->
        nil

      {:ok, {pid, _prefix}} ->
        GenServer.call(pid, {:get_creds, type, ref})
    end
  end

  @spec get_lattice_for_host(host_id :: String.t()) :: nil | String.t()
  def get_lattice_for_host(host_id) do
    # I can't believe I'm saying this, but I wish we had a monad here
    case config(host_id) do
      nil ->
        nil

      config ->
        config.lattice_prefix
    end
  end

  def get_inventory(pid), do: GenServer.call(pid, :get_inventory)

  def full_state(pid) when is_pid(pid) do
    GenServer.call(pid, :get_full_state)
  end

  def config(pid) when is_pid(pid) do
    GenServer.call(pid, :get_config)
  end

  def config(host_id) when is_binary(host_id) do
    case :ets.lookup(:vhost_config_table, host_id) do
      [{_, config}] ->
        config

      [] ->
        Logger.warn("Failed to find config for host ID #{host_id}")
        nil
    end
  end

  def uptime(pid) do
    GenServer.call(pid, :get_uptime)
  end

  def friendly_name(pid) do
    GenServer.call(pid, :get_friendlyname)
  end

  def labels(pid) do
    GenServer.call(pid, :get_labels)
  end

  def generate_ping_reply(pid) do
    GenServer.call(pid, :generate_ping_reply)
  end

  def set_credsmap(pid, credsmap) do
    GenServer.cast(pid, {:put_credsmap, credsmap})
  end

  def stop(pid, timeout_ms) do
    if Process.alive?(pid) do
      GenServer.cast(pid, {:do_stop, timeout_ms})
    end
  end

  def generate_hostinfo_for_provider(host_id, provider_key, link_name, instance_id, config_json) do
    config = config(host_id)

    lds =
      config.lattice_prefix
      |> Manager.get_link_definitions()
      |> Enum.filter(fn %{link_name: ln, provider_id: prov} ->
        ln == link_name && prov == provider_key
      end)

    url =
      if config.prov_rpc_host == nil || config.prov_rpc_host == "" do
        "127.0.0.1:4222"
      else
        "#{config.prov_rpc_host}:#{config.prov_rpc_port}"
      end

    Jason.encode!(%{
      host_id: host_id,
      lattice_rpc_prefix: config.lattice_prefix,
      link_name: link_name,
      lattice_rpc_user_jwt: config.prov_rpc_jwt,
      lattice_rpc_user_seed: config.prov_rpc_seed,
      lattice_rpc_url: url,
      lattice_rpc_tls: config.prov_rpc_tls,
      # for backwards compatibility
      env_values: %{},
      instance_id: instance_id,
      provider_key: provider_key,
      link_definitions: lds,
      config_json: config_json,
      default_rpc_timeout_ms: config.rpc_timeout_ms,
      cluster_issuers: config.cluster_issuers,
      invocation_seed: config.cluster_seed,
      js_domain: config.js_domain,
      # In case providers want to be aware of this for their own logging
      enable_structured_logging: config.enable_structured_logging
    })
  end

  def purge(pid) do
    if Process.alive?(pid), do: GenServer.call(pid, :purge)
  end

  defp do_purge(state) do
    Logger.info(
      "Host purge requested for #{state.config.host_key}, terminating all actors and providers."
    )

    ActorSupervisor.terminate_all(state.config.host_key)
    ProviderSupervisor.terminate_all(state.config.host_key)
  end

  # Callbacks
  @impl true
  def handle_call(:purge, _from, state) do
    do_purge(state)
    {:reply, nil, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call(:get_full_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_inventory, _from, state) do
    {:reply,
     %{
       host_id: state.config.host_key,
       issuer: state.config.cluster_key,
       labels: state.labels,
       friendly_name: state.friendly_name,
       actors: ActorSupervisor.all_actors(state.config.host_key),
       providers: ProviderSupervisor.all_providers(state.config.host_key)
     }, state}
  end

  @impl true
  def handle_call(:get_uptime, _from, state) do
    {total, _} = :erlang.statistics(:wall_clock)
    {:reply, total - state.start_time, state}
  end

  @impl true
  def handle_call(:get_friendlyname, _from, state) do
    {:reply, state.friendly_name, state}
  end

  @impl true
  def handle_call(:get_labels, _from, state) do
    {:reply, state.labels, state}
  end

  @impl true
  def handle_call(:generate_ping_reply, _from, state) do
    {total, _} = :erlang.statistics(:wall_clock)

    ut_seconds = div(total - state.start_time, 1000)

    ut_human =
      ut_seconds
      |> Timex.Duration.from_seconds()
      |> Humanized.format()

    res = %{
      id: state.config.host_key,
      issuer: state.config.cluster_key,
      labels: state.labels,
      friendly_name: state.friendly_name,
      uptime_seconds: ut_seconds,
      uptime_human: ut_human,
      version: :host_core |> Application.spec(:vsn) |> to_string(),
      cluster_issuers: Enum.join(state.config.cluster_issuers, ","),
      js_domain: state.config.js_domain,
      ctl_host: state.config.ctl_host,
      prov_rpc_host: state.config.prov_rpc_host,
      rpc_host: state.config.rpc_host,
      lattice_prefix: state.config.lattice_prefix
    }

    {:reply, res, state}
  end

  def handle_call({:get_creds, type, ref}, _from, state) do
    if state.supplemental_config == nil do
      {:reply, nil, state}
    else
      server_name = extract_server(type, ref)

      with creds_map <- Map.get(state.supplemental_config, "registryCredentials", %{}),
           creds <- Map.get(creds_map, server_name, %{}),
           true <- Map.get(creds, "registryType") == Atom.to_string(type) do
        {:reply, creds, state}
      else
        _ ->
          {:reply, nil, state}
      end
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Host stop requested through process termination: #{inspect(reason)}")

    do_purge(state)
    publish_host_stopped(state)
    :timer.sleep(300)
  end

  @impl true
  def handle_cast({:do_stop, _timeout_ms}, state) do
    Logger.debug("Host stop requested manually")

    do_purge(state)
    publish_host_stopped(state)

    if HostCore.Application.host_count() == 1 do
      # Give a little bit of time for the event to get sent before shutting down
      :timer.sleep(300)

      Task.Supervisor.start_child(
        ControlInterfaceTaskSupervisor,
        fn -> :init.stop() end
      )
    end

    {:stop, :shutdown, state}
  end

  @impl true
  def handle_cast({:put_credsmap, credsmap}, state) do
    # sanitize the incoming map
    credsmap =
      credsmap
      |> Enum.filter(fn {_k, v} ->
        Map.has_key?(v, "registryType") &&
          (Map.has_key?(v, "username") || Map.has_key?(v, "password") || Map.has_key?(v, "token"))
      end)
      |> Enum.map(fn {k, v} ->
        {extract_server(String.to_existing_atom(v["registryType"]), k), v}
      end)
      |> Enum.into(%{})

    new_state =
      case Map.get(state, :supplemental_config) do
        nil ->
          %State{state | supplemental_config: %{"registryCredentials" => credsmap}}

        supp_config ->
          existing_creds = Map.get(supp_config, "registryCredentials", %{})
          merged_creds = Map.merge(existing_creds, credsmap)

          %State{
            state
            | supplemental_config: Map.put(supp_config, "registryCredentials", merged_creds)
          }
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:clear_credsmap}, state) do
    case Map.get(state, :supplemental_config) do
      nil ->
        {:noreply, state}

      supp_config ->
        new_state = %State{
          state
          | supplemental_config: Map.put(supp_config, "registryCredentials", %{})
        }

        {:noreply, new_state}
    end
  end

  defp get_env_host_labels do
    keys =
      System.get_env() |> Map.keys() |> Enum.filter(fn k -> String.starts_with?(k, "HOST_") end)

    Map.new(keys, fn k ->
      {k |> String.slice(5..999) |> String.downcase(), System.get_env(k, "")}
    end)
  end

  defp extract_server(:bindle, s) do
    s
    |> strip_scheme()
    |> String.split("@", trim: true)
    |> Enum.at(-1)
  end

  defp extract_server(:oci, s) do
    s
    |> strip_scheme()
    |> String.split("/")
    |> Enum.at(0)
  end

  defp strip_scheme(s) do
    # remove scheme prefixes
    Enum.reduce(["bindle", "oci", "http", "https"], s, fn scheme, acc ->
      acc |> String.split(scheme <> "://") |> Enum.at(-1)
    end)
  end

  @spec publish_host_started(state :: State.t()) :: :ok
  defp publish_host_started(state) do
    %{
      labels: state.labels,
      friendly_name: state.friendly_name
    }
    |> CloudEvent.new("host_started", state.config.host_key)
    |> CloudEvent.publish(state.config.lattice_prefix)
  end

  @spec publish_host_stopped(state :: State.t()) :: :ok
  defp publish_host_stopped(state) do
    %{
      labels: state.labels
    }
    |> CloudEvent.new("host_stopped", state.config.host_key)
    |> CloudEvent.publish(state.config.lattice_prefix)
  end

  defp start_autostart_provider(prov, state) do
    if !Map.has_key?(prov, "imageReference") || !Map.has_key?(prov, "linkName") do
      Logger.error(
        "Bypassing provider that did not include image reference and link name: #{inspect(prov)}"
      )
    else
      if String.starts_with?(prov["imageReference"], "bindle://") do
        ProviderSupervisor.start_provider_from_bindle(
          state.config.host_key,
          prov["imageReference"],
          prov["linkName"]
        )
      else
        ProviderSupervisor.start_provider_from_oci(
          state.config.host_key,
          prov["imageReference"],
          prov["linkName"]
        )
      end
    end
  end

  defp start_autostart_actor(actor, state) do
    if String.starts_with?(actor, "bindle://") do
      ActorSupervisor.start_actor_from_bindle(state.config.host_key, actor)
    else
      ActorSupervisor.start_actor_from_oci(state.config.host_key, actor)
    end
  end
end
