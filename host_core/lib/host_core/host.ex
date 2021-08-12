defmodule HostCore.Host do
  use GenServer, restart: :transient
  require Logger

  # To set this value in a release, edit the `env.sh` file that is generated
  # by a mix release.

  defmodule State do
    defstruct [:host_key, :lattice_prefix]
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
    configure_ets()

    :ets.insert(:config_table, {:config, opts})

    Logger.info("Host #{opts[:host_key]} started.")
    Logger.info("Valid cluster signers #{opts[:cluster_issuers]}")

    # TODO
    # Once we have a JetStream client, the cache should fill automatically
    # by virtue of us creating ephemeral consumers on the stream for claims, linkdefs, and OCI maps.

    {:ok,
     %State{
       host_key: opts[:host_key],
       lattice_prefix: opts[:lattice_prefix]
     }}
  end

  defp get_env_host_labels() do
    keys =
      System.get_env() |> Map.keys() |> Enum.filter(fn k -> String.starts_with?(k, "HOST_") end)

    Map.new(keys, fn k ->
      {String.slice(k, 5..999) |> String.downcase(), System.get_env(k, "")}
    end)
  end

  @impl true
  def handle_call(:get_labels, _from, state) do
    labels = get_env_host_labels()
    labels = Map.merge(labels, HostCore.WasmCloud.Native.detect_core_host_labels())

    {:reply, labels, state}
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
    case :ets.lookup(:rpc_timeout, :config) do
      [config: config_map] -> config_map[:rpc_timeout]
      _ -> 2_000
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

  def generate_hostinfo_for(provider_key, link_name, instance_id) do
    {url, jwt, seed} =
      case :ets.lookup(:config_table, :config) do
        [config: config_map] ->
          {"#{config_map[:prov_rpc_host]}:#{config_map[:prov_rpc_port]}",
           config_map[:prov_rpc_jwt], config_map[:prov_rpc_seed]}

        _ ->
          {"0.0.0.0:4222", "", ""}
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
      instance_id: instance_id,
      provider_key: provider_key,
      link_definitions: lds,
      # TODO
      env_values: %{},
      invocation_seed: cluster_seed()
    }
    |> Jason.encode!()
  end
end
