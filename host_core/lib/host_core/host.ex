defmodule HostCore.Host do
  use GenServer, restart: :transient
  require Logger

  @thirty_seconds 30_000

  alias HostCore.CloudEvent

  # To set this value in a release, edit the `env.sh` file that is generated
  # by a mix release.

  defmodule State do
    defstruct [:host_key, :host_seed, :lattice_prefix]
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
  * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.get` - Query all link defss for this provider. (queue subscribed)
  * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.del` - Remove a link def.
  * `wasmbus.rpc.{prefix}.claims.put` - Publish discovered claims
  * `wasmbus.rpc.{prefix}.claims.get` - Query all claims (queue subscribed by hosts)
  * `wasmbus.rpc.{prefix}.refmaps.put` - Publish a reference map, e.g. OCI ref -> PK, call alias -> PK
  * `wasmbus.rpc.{prefix}.refmaps.get` - Query all reference maps (queue subscribed by hosts)
  """
  @impl true
  def init(opts) do
    {host_key, host_seed} = HostCore.WasmCloud.Native.generate_key(:server)

    start_gnat(opts)
    configure_ets()

    Logger.info("Host #{host_key} started.")

    Process.send_after(self(), :publish_heartbeat, @thirty_seconds)

    {:ok,
     %State{
       host_key: host_key,
       host_seed: host_seed,
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
  def handle_call(:get_prefix, _from, state) do
    {:reply, state.lattice_prefix, state}
  end

  @impl true
  def handle_call(:get_seed, _from, state) do
    {:reply, state.host_seed, state}
  end

  @impl true
  def handle_call(:get_pk, _from, state) do
    {:reply, state.host_key, state}
  end

  @impl true
  def handle_call(:get_labels, _from, state) do
    labels = get_env_host_labels()
    labels = Map.merge(labels, HostCore.WasmCloud.Native.detect_core_host_labels())

    {:reply, labels, state}
  end

  @impl true
  def handle_info(:publish_heartbeat, state) do
    publish_heartbeat(state)
    Process.send_after(self(), :publish_heartbeat, @thirty_seconds)
    {:noreply, state}
  end

  defp start_gnat(opts) do
    configure_lattice_gnat(%{
      host: opts.rpc_host,
      port: opts.rpc_port,
      username: opts.rpc_user,
      password: opts.rpc_pass,
      token: opts.rpc_token,
      nkey_seed: opts.rpc_seed,
      jwt: opts.rpc_jwt
    })

    configure_control_gnat(%{
      host: opts.ctl_host,
      port: opts.ctl_port,
      username: opts.ctl_user,
      password: opts.ctl_pass,
      token: opts.ctl_token,
      nkey_seed: opts.ctl_seed,
      jwt: opts.ctl_jwt
    })
  end

  defp configure_lattice_gnat(opts) do
    conn_settings =
      Map.merge(%{host: opts.host, port: opts.port}, determine_auth_method(opts, "lattice"))

    case Gnat.start_link(conn_settings, name: :lattice_nats) do
      {:ok, _gnat} ->
        :ok

      {:error, :econnrefused} ->
        Logger.error("Unable to establish lattice NATS connection, connection refused")

      {:error, _} ->
        Logger.error("Authentication to lattice NATS connection failed")
    end
  end

  defp configure_control_gnat(opts) do
    conn_settings =
      Map.merge(
        %{host: opts.host, port: opts.port},
        determine_auth_method(opts, "control interface")
      )

    case Gnat.start_link(conn_settings, name: :control_nats) do
      {:ok, _gnat} ->
        :ok

      {:error, :econnrefused} ->
        Logger.error("Unable to establish control interface NATS connection, connection refused")

      {:error, _} ->
        Logger.error("Authentication to control interface NATS connection failed")
    end
  end

  defp determine_auth_method(
         %{
           username: username,
           password: password,
           token: token,
           nkey_seed: nkey_seed,
           jwt: jwt
         },
         conn_name
       ) do
    cond do
      jwt != "" && nkey_seed != "" ->
        Logger.info("Authenticating to #{conn_name} NATS with JWT and seed")
        %{jwt: jwt, nkey_seed: nkey_seed, auth_required: true}

      nkey_seed != "" ->
        Logger.info("Authenticating to #{conn_name} NATS with seed")
        %{nkey_seed: nkey_seed, auth_required: true}

      token != "" ->
        Logger.info("Authenticating to #{conn_name} NATS with token")
        %{token: token, auth_required: true}

      username != "" && password != "" ->
        Logger.info("Authenticating to #{conn_name} NATS with username and password")
        %{username: username, password: password, auth_required: true}

      # No arguments specified that create a valid authentication method
      true ->
        Logger.info("Connecting to #{conn_name} NATS without authentication")
        %{}
    end
  end

  defp configure_ets() do
    :ets.new(:provider_table, [:named_table, :set, :public])
    :ets.new(:linkdef_table, [:named_table, :set, :public])
    :ets.new(:claims_table, [:named_table, :set, :public])
    :ets.new(:refmap_table, [:named_table, :set, :public])
    :ets.new(:callalias_table, [:named_table, :set, :public])
  end

  def lattice_prefix() do
    GenServer.call(__MODULE__, :get_prefix)
  end

  def seed() do
    GenServer.call(__MODULE__, :get_seed)
  end

  def host_key() do
    GenServer.call(__MODULE__, :get_pk)
  end

  def host_labels() do
    GenServer.call(__MODULE__, :get_labels)
  end

  def generate_hostinfo_for(provider_key, link_name) do
    %{
      host_id: host_key(),
      lattice_rpc_prefix: lattice_prefix(),
      link_name: link_name,
      # TODO
      lattice_rpc_user_jwt: "",
      # TODO
      lattice_rpc_user_seed: "",
      # TODO
      lattice_rpc_url: "",
      provider_key: provider_key,
      # TODO
      env_values: %{}
    }
    |> Jason.encode!()
  end

  def publish_heartbeat(state) do
    topic = "wasmbus.ctl.#{state.lattice_prefix}.events"
    msg = generate_heartbeat(state)
    Gnat.pub(:control_nats, topic, msg)
  end

  defp generate_heartbeat(state) do
    actors =
      HostCore.Actors.ActorSupervisor.all_actors()
      |> Enum.map(fn {k, v} -> %{actor: k, instances: length(v)} end)

    providers =
      HostCore.Providers.ProviderSupervisor.all_providers()
      |> Enum.map(fn {pk, link, contract} ->
        %{public_key: pk, link_name: link, contract_id: contract}
      end)

    %{
      actors: actors,
      providers: providers
    }
    |> CloudEvent.new("host_heartbeat", state.host_key)
  end
end
