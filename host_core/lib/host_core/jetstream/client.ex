defmodule HostCore.Jetstream.Client do
  @moduledoc false
  use GenServer

  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    state = %{
      lattice_prefix: config.lattice_prefix,
      deliver_subject: config.cache_deliver_inbox,
      domain: config.js_domain
    }

    {:ok, state, {:continue, :ensure_stream}}
  end

  @impl true
  def handle_continue(:ensure_stream, state) do
    # TODO get rid of this
    Process.sleep(100)

    create_topic =
      if state.domain == nil do
        "$JS.API.STREAM.CREATE.LATTICECACHE_#{state.lattice_prefix}"
      else
        "$JS.#{state.domain}.API.STREAM.CREATE.LATTICECACHE_#{state.lattice_prefix}"
      end

    stream_topic = "lc.#{state.lattice_prefix}.>"

    payload_json =
      %{
        name: "LATTICECACHE_#{state.lattice_prefix}",
        subjects: [stream_topic],
        retention: "limits",
        max_consumers: -1,
        max_msgs_per_subject: 1,
        max_msgs: -1,
        max_bytes: -1,
        max_age: 0,
        max_msg_size: -1,
        storage: "memory",
        discard: "old",
        num_replicas: 1,
        duplicate_window: 120_000_000_000
      }
      |> Jason.encode!()

    case HostCore.Nats.safe_req(
           HostCore.Nats.control_connection(state.lattice_prefix),
           create_topic,
           payload_json
         ) do
      {:ok, %{body: body}} ->
        handle_stream_create_response(body |> Jason.decode!())

      {:error, :no_responders} ->
        Logger.error("No responders to create stream. Is JetStream enabled/configured properly?")

      {:error, :timeout} ->
        Logger.error(
          "Failed to receive create stream ACK from JetStream within timeout. Is JetStream enabled?"
        )
    end

    {:noreply, state, {:continue, :create_eph_consumer}}
  end

  @impl true
  def handle_continue(:create_eph_consumer, state) do
    Logger.info("Attempting to create ephemeral consumer (cache loader)", js_domain: state.domain)
    stream_name = "LATTICECACHE_#{state.lattice_prefix}"
    consumer_name = String.replace(state.deliver_subject, "_INBOX.", "")

    create_topic =
      if state.domain == nil do
        "$JS.API.CONSUMER.CREATE.#{stream_name}"
      else
        "$JS.#{state.domain}.API.CONSUMER.CREATE.#{stream_name}"
      end

    payload_json =
      %{
        stream_name: stream_name,
        name: consumer_name,
        config: %{
          description: "cache loader for #{state.lattice_prefix}",
          ack_policy: "explicit",
          filter_subject: ">",
          deliver_policy: "last_per_subject",
          deliver_subject: state.deliver_subject,
          max_ack_pending: 20_000,
          max_deliver: -1,
          replay_policy: "instant"
        }
      }
      |> Jason.encode!()

    case HostCore.Nats.safe_req(
           HostCore.Nats.control_connection(state.lattice_prefix),
           create_topic,
           payload_json
         ) do
      {:ok, %{body: body}} ->
        handle_consumer_create_response(body |> Jason.decode!())

      {:error, :no_responders} ->
        Logger.error(
          "No responders to attempt to create JS consumer. Is JetStream enabled/configured properly?"
        )

      {:error, :timeout} ->
        Logger.error(
          "Failed to receive create consumer ACK from JetStream within timeout. Ensure JetStream is enabled on your NATS server."
        )
    end

    {:noreply, state}
  end

  def handle_consumer_create_response(%{
        "type" => "io.nats.jetstream.api.v1.consumer_create_response",
        "error" => %{
          "code" => code,
          "description" => desc
        }
      }) do
    Logger.error("Failed to create ephemeral cache loader consumer (#{code}) - #{desc}")
  end

  def handle_consumer_create_response(%{
        "type" => "io.nats.jetstream.api.v1.consumer_create_response",
        "config" => _config
      }) do
    Logger.info("Created ephemeral consumer for lattice cache loader")
  end

  def handle_stream_create_response(%{
        "type" => "io.nats.jetstream.api.v1.stream_create_response",
        "config" => _config,
        "state" => state
      }) do
    Logger.info(
      "Lattice cache stream created or verified as existing (#{state["consumer_count"]} consumers)."
    )
  end

  def handle_stream_create_response(%{
        "type" => "io.nats.jetstream.api.v1.stream_create_response",
        "error" => %{
          "code" => 500,
          "description" => "stream name already in use"
        }
      }) do
    Logger.info("Lattice cache stream name already in use, assuming previously-configured stream")
  end

  # This is almost identical to above, but for some reason when the stream has multiple replicas,
  # this returns a 400 error code rather than 500
  def handle_stream_create_response(%{
        "type" => "io.nats.jetstream.api.v1.stream_create_response",
        "error" => %{
          "code" => 400,
          "description" => "stream name already in use"
        }
      }) do
    Logger.info("Lattice cache stream name already in use, assuming previously-configured stream")
  end

  def handle_stream_create_response(%{
        "type" => "io.nats.jetstream.api.v1.stream_create_response",
        "error" => %{
          "code" => 400,
          "description" => "stream name already in use with a different configuration"
        }
      }) do
    Logger.info(
      "Lattice cache stream name already in use with different configuration, using previously-configured stream"
    )
  end

  def handle_stream_create_response(%{
        "error" => %{
          "code" => 500,
          "description" => "subjects overlap with an existing stream"
        },
        "type" => "io.nats.jetstream.api.v1.stream_create_response"
      }) do
    Logger.info(
      "Lattice cache stream subjects already configured, assuming previously-configured stream"
    )
  end

  def handle_stream_create_response(body) do
    Logger.warn(
      "Received unexpected response from NATS when attempting to create cache stream: #{inspect(body)}"
    )
  end
end
