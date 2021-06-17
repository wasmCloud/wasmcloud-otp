defmodule HostCore.Actors.ActorModule do
  # Do not automatically restart this process
  use GenServer, restart: :transient

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
      :api_version,
      :invocation,
      :claims
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

  def halt(pid) do
    GenServer.call(pid, :halt_and_cleanup)
  end

  @impl true
  def init({claims, bytes}) do
    start_actor(claims, bytes)
  end

  def handle_call(:get_api_ver, _from, agent) do
    {:reply, Agent.get(agent, fn content -> content.api_version end), agent}
  end

  def handle_call(:get_claims, _from, agent) do
    {:reply, Agent.get(agent, fn content -> content.claims end), agent}
  end

  @impl true
  def handle_call(:get_invocation, _from, agent) do
    Logger.info("Getting invocation")
    {:reply, Agent.get(agent, fn content -> content.invocation end), agent}
  end

  @impl true
  def handle_call(:halt_and_cleanup, _from, agent) do
    # Add cleanup if necessary here...
    Logger.info("Actor instance termination requested")

    {:stop, :normal, :ok, agent}
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
    # TODO - handle failure
    {:ok, inv} = Msgpax.unpack(body)
    # TODO - perform antiforgery check
    # TODO error handle
    # TODO refactor perform invocation so it's not required to run from inside handle_call
    {:ok, response} = perform_invocation(agent, inv["operation"], inv["msg"])

    ir = %{
      msg: response,
      invocation_id: inv["id"]
    }

    Gnat.pub(:lattice_nats, reply_to, ir |> Msgpax.pack!() |> IO.iodata_to_binary())
    {:noreply, agent}
  end

  defp start_actor(claims, bytes) do
    Registry.register(Registry.ActorRegistry, claims.public_key, claims)
    HostCore.ClaimsManager.put_claims(claims)

    {:ok, agent} = Agent.start_link(fn -> %State{claims: claims} end)

    if claims.call_alias != nil do
      # TODO put call alias into a ref map
    end

    prefix = HostCore.Host.lattice_prefix()

    {:ok, _subscription} =
      Gnat.sub(:lattice_nats, self(), "wasmbus.rpc.#{prefix}.#{claims.public_key}")

    imports = %{
      wapc: Imports.wapc_imports(agent),
      frodobuf: Imports.frodobuf_imports(agent)
    }

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

  defp prepare_module({:ok, instance}, agent) do
    api_version =
      case Wasmex.call_function(instance, :__frodobuf_api_version, []) do
        {:ok, [v]} -> v
        _ -> 0
      end

    claims = Agent.get(agent, fn content -> content.claims end)
    Wasmex.call_function(instance, :start, [])
    Wasmex.call_function(instance, :wapc_init, [])

    Agent.update(agent, fn content ->
      %State{content | api_version: api_version, instance: instance}
    end)

    publish_actor_started(claims.public_key)
    {:ok, agent}
  end

  def publish_actor_started(actor_pk) do
    prefix = HostCore.Host.lattice_prefix()
    stamp = DateTime.utc_now() |> DateTime.to_iso8601()
    host = HostCore.Host.host_key()

    msg =
      %{
        specversion: "1.0",
        time: stamp,
        type: "com.wasmcloud.lattice.actor_started",
        source: "#{host}",
        datacontenttype: "application/json",
        id: UUID.uuid4(),
        data: %{
          public_key: actor_pk
        }
      }
      |> Cloudevents.from_map!()
      |> Cloudevents.to_json()

    topic = "wasmbus.ctl.#{prefix}.events"

    Gnat.pub(:control_nats, topic, msg)
  end

  def publish_actor_stopped(actor_pk, remaining_count) do
    prefix = HostCore.Host.lattice_prefix()
    stamp = DateTime.utc_now() |> DateTime.to_iso8601()
    host = HostCore.Host.host_key()

    msg =
      %{
        specversion: "1.0",
        time: stamp,
        type: "com.wasmcloud.lattice.actor_stopped",
        source: "#{host}",
        datacontenttype: "application/json",
        id: UUID.uuid4(),
        data: %{
          public_key: actor_pk,
          running_instances: remaining_count
        }
      }
      |> Cloudevents.from_map!()
      |> Cloudevents.to_json()

    topic = "wasmbus.ctl.#{prefix}.events"

    Gnat.pub(:control_nats, topic, msg)
  end
end
