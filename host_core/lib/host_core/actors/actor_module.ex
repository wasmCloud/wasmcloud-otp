defmodule HostCore.Actors.ActorModule do
  @moduledoc false
  # Do not automatically restart this process
  use GenServer, restart: :transient
  alias HostCore.CloudEvent

  @op_health_check "Actor.HealthRequest"
  @thirty_seconds 30_000

  require Logger
  alias HostCore.WebAssembly.Imports

  defmodule State do
    @moduledoc false

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
      :ociref,
      :healthy
    ]
  end

  defmodule Invocation do
    @moduledoc false
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
    if Process.alive?(pid) do
      GenServer.call(pid, :get_claims)
    else
      %{}
    end
  end

  def ociref(pid) do
    GenServer.call(pid, :get_ociref)
  end

  def instance_id(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_instance_id)
    else
      "??"
    end
  end

  def halt(pid) do
    if Process.alive?(pid), do: GenServer.call(pid, :halt_and_cleanup)
  end

  def health_check(pid) do
    if Process.alive?(pid), do: GenServer.call(pid, :health_check)
  end

  def live_update(pid, bytes, claims, oci) do
    GenServer.call(pid, {:live_update, bytes, claims, oci}, @thirty_seconds)
  end

  @impl true
  def init({claims, bytes, oci}) do
    case start_actor(claims, bytes, oci) do
      {:ok, agent} ->
        Process.send(self(), :do_health, [:noconnect, :nosuspend])
        :timer.send_interval(@thirty_seconds, self(), :do_health)
        {:ok, agent}

      {:error, _e} ->
        # Actor should stop with no adverse effects on the supervisor
        :ignore
    end
  end

  def handle_call({:live_update, bytes, claims, oci}, _from, agent) do
    Logger.debug("Actor #{claims.public_key} performing live update",
      actor_id: claims.public_key,
      oci_ref: oci
    )

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
      %State{state | claims: claims, api_version: api_version, instance: instance, ociref: oci}
    end)

    Wasmex.call_function(instance, :start, [])
    Wasmex.call_function(instance, :wapc_init, [])

    publish_actor_updated(claims.public_key, claims.revision, instance_id)

    Logger.debug("Actor #{claims.public_key} live update complete",
      actor_id: claims.public_key,
      oci_ref: oci
    )

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
    {:reply, Agent.get(agent, fn content -> content.invocation end), agent}
  end

  @impl true
  def handle_call(:health_check, _from, agent) do
    {:reply, perform_health_check(agent), agent}
  end

  @impl true
  def handle_call(:halt_and_cleanup, _from, agent) do
    # Add cleanup if necessary here...
    subscription = Agent.get(agent, fn content -> content.subscription end)
    public_key = Agent.get(agent, fn content -> content.claims.public_key end)
    Logger.debug("Actor instance termination requested", actor_id: public_key)
    instance_id = Agent.get(agent, fn content -> content.instance_id end)

    Gnat.unsub(:lattice_nats, subscription)
    publish_actor_stopped(public_key, instance_id)

    {:stop, :normal, :ok, agent}
  end

  @impl true
  def handle_info(:do_health, agent) do
    perform_health_check(agent)
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
    Logger.debug("Received invocation on #{topic}")
    iid = Agent.get(agent, fn content -> content.instance_id end)

    {ir, inv} =
      with {:ok, inv} <- Msgpax.unpack(body) do
        case HostCore.WasmCloud.Native.validate_antiforgery(body, HostCore.Host.cluster_issuers()) do
          {:error, msg} ->
            Logger.error("Invocation failed anti-forgery validation check: #{msg}",
              invocation_id: inv["id"]
            )

            {%{
               msg: nil,
               invocation_id: inv["id"],
               error: msg,
               instance_id: iid
             }, inv}

          _ ->
            case validate_invocation(
                   agent,
                   inv["origin"]["link_name"],
                   inv["origin"]["contract_id"]
                 )
                 |> perform_invocation(
                   inv["operation"],
                   check_dechunk_inv(inv["id"], inv["content_length"], Map.get(inv, "msg", <<>>))
                   |> IO.iodata_to_binary()
                 ) do
              {:ok, response} ->
                {%{
                   msg: response,
                   invocation_id: inv["id"],
                   instance_id: iid,
                   content_length: byte_size(response)
                 }
                 |> chunk_inv_response(), inv}

              {:error, error} ->
                Logger.error("Invocation failure: #{error}", invocation_id: inv["id"])

                {%{
                   msg: nil,
                   error: error,
                   invocation_id: inv["id"],
                   instance_id: iid
                 }, inv}
            end
        end
      else
        _ ->
          {%{
             msg: nil,
             invocation_id: "",
             error: "Failed to deserialize msgpack invocation",
             instance_id: iid
           }, nil}
      end

    HostCore.Nats.safe_pub(:lattice_nats, reply_to, ir |> Msgpax.pack!() |> IO.iodata_to_binary())

    Task.start(fn ->
      publish_invocation_result(inv, ir)
    end)

    {:noreply, agent}
  end

  # Invocation responses are stored in the chunked object store with a `-r` appended
  # to the end of the invocation ID
  defp chunk_inv_response(
         %{
           msg: response,
           invocation_id: invid,
           instance_id: _iid
         } = map
       )
       when byte_size(response) > 700 * 1024 do
    with :ok <- HostCore.WasmCloud.Native.chunk_inv("#{invid}-r", response) do
      %{map | msg: nil}
    else
      _ ->
        map
    end
  end

  defp chunk_inv_response(map), do: map

  defp check_dechunk_inv(_, nil, bytes), do: bytes

  # Check if we need to download an artifact from the object store
  # which will be when the content-length of an invocation is > 0 and
  # the size of the `msg` binary is 0
  defp check_dechunk_inv(inv_id, content_length, bytes) do
    if content_length > byte_size(bytes) do
      Logger.debug("Dechunking #{content_length} from object store for #{inv_id}",
        invocation_id: inv_id
      )

      HostCore.WasmCloud.Native.dechunk_inv(inv_id)
    else
      bytes
    end
  end

  defp start_actor(claims, bytes, oci) do
    Logger.info("Starting actor #{claims.public_key}", actor_id: claims.public_key, oci_ref: oci)
    Registry.register(Registry.ActorRegistry, claims.public_key, claims)
    HostCore.Claims.Manager.put_claims(claims)

    {:ok, agent} =
      Agent.start_link(fn -> %State{claims: claims, instance_id: UUID.uuid4(), healthy: false} end)

    imports = %{
      wapc: Imports.wapc_imports(agent),
      wasmbus: Imports.wasmbus_imports(agent),
      wasi_snapshot_preview1: Imports.fake_wasi(agent)
    }

    case Wasmex.start_link(%{bytes: bytes, imports: imports}) |> prepare_module(agent, oci) do
      {:ok, agent} ->
        prefix = HostCore.Host.lattice_prefix()
        topic = "wasmbus.rpc.#{prefix}.#{claims.public_key}"

        Logger.debug("Subscribing to #{topic}")
        {:ok, subscription} = Gnat.sub(:lattice_nats, self(), topic, queue_group: topic)

        Agent.update(agent, fn state ->
          %State{state | subscription: subscription, ociref: oci}
        end)

        publish_oci_map(oci, claims.public_key)
        {:ok, agent}

      {:error, e} ->
        Logger.error("Failed to start actor: #{inspect(e)}", actor_id: claims.public_key)
        HostCore.ControlInterface.Server.publish_actor_start_failed(claims.public_key, inspect(e))
        {:error, e}
    end
  end

  # Actor-to-actor calls are always allowed
  defp validate_invocation(agent, "", "") do
    {agent, true}
  end

  # Actor-to-actor calls are always allowed
  defp validate_invocation(agent, nil, nil) do
    {agent, true}
  end

  defp validate_invocation(agent, _link_name, contract_id) do
    caps = Agent.get(agent, fn contents -> contents.claims.caps end)
    {agent, Enum.member?(caps, contract_id)}
  end

  defp perform_invocation({agent, true}, operation, payload) do
    raw_state = Agent.get(agent, fn content -> content end)

    Logger.debug("performing invocation #{operation}",
      operation: operation,
      actor_id: raw_state.claims.public_key
    )

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

    # invoke __guest_call
    # if it fails, set guest_error, return 1
    # if it succeeeds, set guest_response, return 0
    Wasmex.call_function(raw_state.instance, :__guest_call, [
      byte_size(operation),
      byte_size(payload)
    ])
    |> to_guest_call_result(agent)
  end

  defp perform_invocation({_agent, false}, operation, _payload) do
    Logger.error("Actor does not have proper capabilities to receive this invocation",
      operation: operation
    )

    {:error, "actor is missing capability claims"}
  end

  defp to_guest_call_result({:ok, [res]}, agent) do
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
        perform_invocation({agent, true}, @op_health_check, payload)
      rescue
        _e -> {:error, "Failed to invoke actor module"}
      end

    case res do
      {:ok, _payload} ->
        if !Agent.get(agent, fn contents -> contents.healthy end) do
          publish_check_passed(agent)
          Agent.update(agent, fn contents -> %State{contents | healthy: true} end)
        end

      {:error, reason} ->
        Logger.debug("Actor health check failed: #{reason}")

        if Agent.get(agent, fn contents -> contents.healthy end) do
          publish_check_failed(agent, reason)
          Agent.update(agent, fn contents -> %State{contents | healthy: false} end)
        end
    end

    res
  end

  defp prepare_module({:error, e}, _agent, _oci), do: {:error, e}

  defp prepare_module({:ok, instance}, agent, oci) do
    api_version =
      case Wasmex.call_function(instance, :__wasmbus_rpc_version, []) do
        {:ok, [v]} -> v
        _ -> 0
      end

    claims = Agent.get(agent, fn content -> content.claims end)
    instance_id = Agent.get(agent, fn content -> content.instance_id end)

    if Wasmex.function_exists(instance, :start) do
      Wasmex.call_function(instance, :start, [])
    end

    if Wasmex.function_exists(instance, :wapc_init) do
      Wasmex.call_function(instance, :wapc_init, [])
    end

    # TinyGo exports `main` as `_start`
    if Wasmex.function_exists(instance, :_start) do
      Wasmex.call_function(instance, :_start, [])
    end

    Agent.update(agent, fn content ->
      %State{content | api_version: api_version, instance: instance}
    end)

    publish_actor_started(claims, api_version, instance_id, oci)
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

  defp publish_invocation_result(inv, inv_r) do
    prefix = HostCore.Host.lattice_prefix()

    origin = inv["origin"]
    target = inv["target"]

    evt_type =
      if Map.get(inv_r, :error) == nil do
        "invocation_succeeded"
      else
        "invocation_failed"
      end

    msg =
      %{
        source: %{
          public_key: origin["public_key"],
          contract_id: Map.get(origin, "contract_id"),
          link_name: Map.get(origin, "link_name")
        },
        dest: %{
          public_key: target["public_key"],
          contract_id: Map.get(target, "contract_id"),
          link_name: Map.get(target, "link_name")
        },
        operation: inv["operation"],
        bytes: byte_size(Map.get(inv, "msg", ""))
      }
      |> CloudEvent.new(evt_type)

    topic = "wasmbus.evt.#{prefix}"
    HostCore.Nats.safe_pub(:control_nats, topic, msg)
  end

  def publish_actor_started(claims, api_version, instance_id, oci) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: claims.public_key,
        image_ref: oci,
        api_version: api_version,
        instance_id: instance_id,
        claims: %{
          call_alias: claims.call_alias,
          caps: claims.caps,
          issuer: claims.issuer,
          tags: claims.tags,
          name: claims.name,
          version: claims.version,
          revision: claims.revision,
          not_before_human: claims.not_before_human,
          expires_human: claims.expires_human
        }
      }
      |> CloudEvent.new("actor_started")

    topic = "wasmbus.evt.#{prefix}"

    HostCore.Nats.safe_pub(:control_nats, topic, msg)
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

    HostCore.Nats.safe_pub(:control_nats, topic, msg)
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

    HostCore.Nats.safe_pub(:control_nats, topic, msg)
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
    HostCore.Nats.safe_pub(:control_nats, topic, msg)

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
    HostCore.Nats.safe_pub(:control_nats, topic, msg)

    nil
  end
end
