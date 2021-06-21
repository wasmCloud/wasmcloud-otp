defmodule HostCore.Host do
  use GenServer, restart: :transient
  require Logger

  # To set this value in a release, edit the `env.sh` file that is generated
  # by a mix release.
  @prefix_var "WASMCLOUD_LATTICE_PREFIX"
  @default_prefix "default"

  defmodule State do
    defstruct [:host_key, :host_seed, :labels]
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
  * `wasmbus.rpc.{prefix}.ref_maps.put` - Publish a reference map, e.g. OCI ref -> PK, call alias -> PK
  * `wasmbus.rpc.{prefix}.ref_maps.get` - Query all reference maps (queue subscribed by hosts)
  """
  @impl true
  def init(_opts) do
    {host_key, host_seed} = HostCore.WasmCloud.Native.generate_key(:server)

    configure_ets()

    Logger.info("Host #{host_key} started.")

    # TODO - get namespace prefix from env/config
    # TODO - query intrinsic labels for OS/CPU family
    # TODO - append labels from env/config
    {:ok,
     %State{
       host_key: host_key,
       host_seed: host_seed
     }}
  end

  @impl true
  def handle_call(:get_prefix, _from, state) do
    {:reply, System.get_env(@prefix_var, @default_prefix), state}
  end

  @impl true
  def handle_call(:get_seed, _from, state) do
    {:reply, state.host_seed, state}
  end

  @impl true
  def handle_call(:get_pk, _from, state) do
    {:reply, state.host_key, state}
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
end
