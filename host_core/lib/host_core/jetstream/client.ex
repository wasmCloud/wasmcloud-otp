defmodule HostCore.Jetstream.Client do
  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    state = %{
      lattice_prefix: config.lattice_prefix,
      deliver_subject: config.cache_deliver_inbox
    }

    {:ok, state, {:continue, :ensure_stream}}
  end

  @impl true
  def handle_continue(:ensure_stream, state) do
    # TODO get rid of this
    Process.sleep(100)
    create_topic = "$JS.API.STREAM.CREATE.LATTICECACHE_#{state.lattice_prefix}"
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

    cont =
      case Gnat.request(:control_nats, create_topic, payload_json) do
        {:ok, %{body: body}} ->
          handle_stream_create_response(body |> Jason.decode!())

        {:error, :timeout} ->
          Logger.error(
            "Failed to receive create stream ACK from JetStream. Is JetStream enabled?"
          )

          false
      end

    if cont do
      {:noreply, state, {:continue, :create_eph_consumer}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_continue(:create_eph_consumer, state) do
    Logger.info("Attempting to create ephemeral consumer (cache loader)")
    stream_name = "LATTICECACHE_#{state.lattice_prefix}"
    consumer_name = String.replace(state.deliver_subject, "_INBOX.", "")
    create_topic = "$JS.API.CONSUMER.CREATE.#{stream_name}"

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
          # idle_heartbeat: 2_000_000_000,
          max_ack_pending: 20000,
          max_deliver: -1,
          replay_policy: "instant"
        }
      }
      |> Jason.encode!()

    case Gnat.request(:control_nats, create_topic, payload_json) do
      {:ok, %{body: body}} ->
        handle_consumer_create_response(body |> Jason.decode!())

      {:error, :timeout} ->
        Logger.error("Failed to receive create consumer ACK from JetStream.")
        false
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
        "state" => _state
      }) do
    Logger.info("Default lattice cache stream created or verified as existing")
    true
  end

  def handle_stream_create_response(%{
        "type" => "io.nats.jetstream.api.v1.stream_create_response",
        "error" => %{
          "code" => 500,
          "description" => "stream name already in use"
        }
      }) do
    Logger.info("Lattice cache stream name already in use, assuming previously-configured stream")
    true
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

    true
  end

  def handle_stream_create_response(body) do
    Logger.error(
      "Received unexpected response from NATS when attempting to create cache stream: #{inspect(body)}"
    )

    false
  end
end
