defmodule HostCore.Actors.ActorModule do
  # Do not automatically restart this process
  use GenServer, restart: :transient
  alias HostCore.CloudEvent

  @op_health_check "HealthRequest"
  @thirty_seconds 30_000

  require Logger
  alias HostCore.WebAssembly.Imports

  defmodule State do
    defstruct [
      :guest_request,
      :guest_response,
      :host_response,
      :guest_error,
      :host_error,
      :instance,
      :instance_id,
      :api_version,
      :invocation,
      :claims,
      :subscription,
      :ociref
    ]
  end

  defmodule Invocation do
    defstruct [:operation, :payload]
  end

  @doc """
  Starts the Actor module
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def current_invocation(pid) do
    GenServer.call(pid, :get_invocation)
  end

  def api_version(pid) do
    GenServer.call(pid, :get_api_ver)
  end

  def claims(pid) do
    GenServer.call(pid, :get_claims)
  end

  def instance_id(pid) do
    GenServer.call(pid, :get_instance_id)
  end

  def ociref(pid) do
    GenServer.call(pid, :get_ociref)
  end

  def halt(pid) do
    GenServer.call(pid, :halt_and_cleanup)
  end

  def health_check(pid) do
    GenServer.call(pid, :health_check)
  end

  def live_update(pid, bytes, claims) do
    GenServer.call(pid, {:live_update, bytes, claims}, @thirty_seconds)
  end

  @impl true
  def init({claims, bytes, oci}) do
    start_actor(claims, bytes, oci)
  end

  def handle_call({:live_update, bytes, claims}, _from, agent) do
    Logger.debug("Actor #{claims.public_key} performing live update")

    imports = %{
      wapc: Imports.wapc_imports(agent),
      wasmbus: Imports.wasmbus_imports(agent)
    }

    # shut down the previous Wasmex instance to avoid orphaning it
    old_instance = Agent.get(agent, fn content -> content.instance end)
    GenServer.stop(old_instance, :normal)

    instance_id = Agent.get(agent, fn content -> content.instance_id end)

    {:ok, instance} = Wasmex.start_link(%{bytes: bytes, imports: imports})

    api_version =
      case Wasmex.call_function(instance, :__wasmbus_rpc_version, []) do
        {:ok, [v]} -> v
        _ -> 0
      end

    Agent.update(agent, fn state ->
      %State{state | claims: claims, api_version: api_version, instance: instance}
    end)

    Wasmex.call_function(instance, :start, [])
    Wasmex.call_function(instance, :wapc_init, [])

    publish_actor_updated(claims.public_key, claims.revision, instance_id)
    Logger.debug("Actor #{claims.public_key} updated")
    {:reply, :ok, agent}
  end

  def handle_call(:get_api_ver, _from, agent) do
    {:reply, Agent.get(agent, fn content -> content.api_version end), agent}
  end

  def handle_call(:get_claims, _from, agent) do
    {:reply, Agent.get(agent, fn content -> content.claims end), agent}
  end

  def handle_call(:get_instance_id, _from, agent) do
    {:reply, Agent.get(agent, fn content -> content.instance_id end), agent}
  end

  def handle_call(:get_ociref, _from, agent) do
    {:reply, Agent.get(agent, fn content -> content.ociref end), agent}
  end

  @impl true
  def handle_call(:get_invocation, _from, agent) do
    Logger.info("Getting invocation")
    {:reply, Agent.get(agent, fn content -> content.invocation end), agent}
  end

  @impl true
  def handle_call(:health_check, _from, agent) do
    {:reply, perform_health_check(agent), agent}
  end

  @impl true
  def handle_call(:halt_and_cleanup, _from, agent) do
    # Add cleanup if necessary here...
    Logger.info("Actor instance termination requested")
    subscription = Agent.get(agent, fn content -> content.subscription end)
    public_key = Agent.get(agent, fn content -> content.claims.public_key end)
    instance_id = Agent.get(agent, fn content -> content.instance_id end)

    Gnat.unsub(:lattice_nats, subscription)
    publish_actor_stopped(public_key, instance_id)

    {:stop, :normal, :ok, agent}
  end

  @impl true
  def handle_info(:do_health, agent) do
    perform_health_check(agent)
    Process.send_after(self(), :do_health, @thirty_seconds)
    {:noreply, agent}
  end

  @impl true
  def handle_info(
        {:msg,
         %{
           body: body,
           reply_to: reply_to,
           topic: topic
         }},
        agent
      ) do
    Logger.info("Received invocation on #{topic}")
    iid = Agent.get(agent, fn content -> content.instance_id end)
    # TODO - handle failure
    ir =
      with {:ok, inv} <- Msgpax.unpack(body) do
        case HostCore.WasmCloud.Native.validate_antiforgery(body, HostCore.Host.cluster_issuers()) do
          {:error, msg} ->
            %{
              msg: nil,
              invocation_id: inv["id"],
              error: msg,
              instance_id: iid
            }

          _ ->
            case perform_invocation(agent, inv["operation"], inv["msg"]) do
              {:ok, response} ->
                %{
                  msg: response,
                  invocation_id: inv["id"],
                  instance_id: iid
                }

              {:error, error} ->
                %{
                  msg: nil,
                  error: error,
                  invocation_id: inv["id"],
                  instance_id: iid
                }
            end
        end
      else
        _ ->
          %{
            msg: nil,
            invocation_id: "",
            error: "Failed to deserialize msgpack invocation",
            instance_id: iid
          }
      end

    Gnat.pub(:lattice_nats, reply_to, ir |> Msgpax.pack!() |> IO.iodata_to_binary())
    {:noreply, agent}
  end

  defp start_actor(claims, bytes, oci) do
    Logger.info("Actor module starting")
    Registry.register(Registry.ActorRegistry, claims.public_key, claims)
    HostCore.Claims.Manager.put_claims(claims)

    {:ok, agent} = Agent.start_link(fn -> %State{claims: claims, instance_id: UUID.uuid4()} end)

    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.#{claims.public_key}"

    Logger.info("Subscribing to #{topic}")
    {:ok, subscription} = Gnat.sub(:lattice_nats, self(), topic, queue_group: topic)
    Agent.update(agent, fn state -> %State{state | subscription: subscription, ociref: oci} end)

    Process.send_after(self(), :do_health, @thirty_seconds)

    imports = %{
      wapc: Imports.wapc_imports(agent),
      wasmbus: Imports.wasmbus_imports(agent)
    }

    publish_oci_map(oci, claims.public_key)

    Wasmex.start_link(%{bytes: bytes, imports: imports})
    |> prepare_module(agent)
  end

  defp perform_invocation(agent, operation, payload) do
    Logger.info("performing invocation #{operation}")
    raw_state = Agent.get(agent, fn content -> content end)

    raw_state = %State{
      raw_state
      | guest_response: nil,
        guest_request: nil,
        guest_error: nil,
        host_response: nil,
        host_error: nil,
        invocation: %Invocation{operation: operation, payload: payload}
    }

    Agent.update(agent, fn _content -> raw_state end)
    Logger.info("Agent state updated")

    # invoke __guest_call
    # if it fails, set guest_error, return 1
    # if it succeeeds, set guest_response, return 0
    Wasmex.call_function(raw_state.instance, :__guest_call, [
      byte_size(operation),
      byte_size(payload)
    ])
    |> to_guest_call_result(agent)
  end

  defp to_guest_call_result({:ok, [res]}, agent) do
    Logger.info("OK result")
    state = Agent.get(agent, fn content -> content end)

    case res do
      1 -> {:ok, state.guest_response}
      0 -> {:error, state.guest_error}
    end
  end

  defp to_guest_call_result({:error, err}, _agent) do
    {:error, err}
  end

  defp perform_health_check(agent) do
    payload = %{placeholder: true} |> Msgpax.pack!() |> IO.iodata_to_binary()

    res =
      try do
        perform_invocation(agent, @op_health_check, payload)
      rescue
        _e -> {:error, "Failed to invoke actor module"}
      end

    case res do
      {:ok, _payload} -> publish_check_passed(agent)
      {:error, reason} -> publish_check_failed(agent, reason)
    end

    res
  end

  defp prepare_module({:ok, instance}, agent) do
    api_version =
      case Wasmex.call_function(instance, :__wasmbus_rpc_version, []) do
        {:ok, [v]} -> v
        _ -> 0
      end

    claims = Agent.get(agent, fn content -> content.claims end)
    instance_id = Agent.get(agent, fn content -> content.instance_id end)
    Wasmex.call_function(instance, :start, [])
    Wasmex.call_function(instance, :wapc_init, [])

    Agent.update(agent, fn content ->
      %State{content | api_version: api_version, instance: instance}
    end)

    publish_actor_started(claims.public_key, api_version, instance_id)
    {:ok, agent}
  end

  def publish_oci_map("", _pk) do
    # No Op
  end

  def publish_oci_map(nil, _pk) do
    # No Op
  end

  def publish_oci_map(oci, pk) do
    HostCore.Refmaps.Manager.put_refmap(oci, pk)
  end

  def publish_actor_started(actor_pk, api_version, instance_id) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: actor_pk,
        api_version: api_version,
        instance_id: instance_id
      }
      |> CloudEvent.new("actor_started")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  def publish_actor_updated(actor_pk, revision, instance_id) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: actor_pk,
        revision: revision,
        instance_id: instance_id
      }
      |> CloudEvent.new("actor_updated")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  def publish_actor_stopped(actor_pk, instance_id) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: actor_pk,
        instance_id: instance_id
      }
      |> CloudEvent.new("actor_stopped")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  defp publish_check_passed(agent) do
    prefix = HostCore.Host.lattice_prefix()
    claims = Agent.get(agent, fn content -> content.claims end)
    iid = Agent.get(agent, fn content -> content.instance_id end)

    msg =
      %{
        public_key: claims.public_key,
        instance_id: iid
      }
      |> CloudEvent.new("health_check_passed")

    topic = "wasmbus.evt.#{prefix}"
    Gnat.pub(:control_nats, topic, msg)

    nil
  end

  defp publish_check_failed(agent, reason) do
    prefix = HostCore.Host.lattice_prefix()
    claims = Agent.get(agent, fn content -> content.claims end)
    iid = Agent.get(agent, fn content -> content.instance_id end)

    msg =
      %{
        public_key: claims.public_key,
        instance_id: iid,
        reason: reason
      }
      |> CloudEvent.new("health_check_failed")

    topic = "wasmbus.evt.#{prefix}"
    Gnat.pub(:control_nats, topic, msg)

    nil
  end
end
