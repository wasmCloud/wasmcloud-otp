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
      legacy_deliver_subject: config.cache_deliver_inbox,
      metadata_deliver_subject: config.metadata_deliver_inbox,
      domain: config.js_domain
    }

    {:ok, state, {:continue, :ensure_stream}}
  end

  @impl true
  def handle_continue(:ensure_stream, state) do
    for _i <- 0..3 do
      if Process.whereis(HostCore.Nats.control_connection(state.lattice_prefix)) == nil do
        Process.sleep(200)
      end
    end

    {create_topic, stream_topic} =
      if state.domain == nil do
        {"$JS.API.STREAM.CREATE.KV_WCMDCACHE_#{state.lattice_prefix}",
         "$KV.WCMDCACHE_#{state.lattice_prefix}.>"}
      else
        {"$JS.#{state.domain}.API.STREAM.CREATE.KV_WCMDCACHE_#{state.lattice_prefix}",
         "$KV.#{state.domain}.WCMDCACHE_#{state.lattice_prefix}.>"}
      end

    payload_json =
      %{
        name: "KV_WCMDCACHE_#{state.lattice_prefix}",
        subjects: [stream_topic],
        retention: "limits",
        max_consumers: -1,
        max_msgs_per_subject: 1,
        max_msgs: -1,
        max_bytes: -1,
        allow_direct: true,
        mirror_direct: false,
        deny_delete: true,
        sealed: false,
        deny_purge: false,
        allow_rollup_hdrs: true,
        max_age: 0,
        max_msg_size: -1,
        storage: "file",
        discard: "new",
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
    Logger.info("Attempting to create ephemeral consumer (metadata loader)",
      js_domain: state.domain
    )

    stream_name = "KV_WCMDCACHE_#{state.lattice_prefix}"
    consumer_name = String.replace(state.metadata_deliver_subject, "_INBOX.", "")

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
          description: "metadata loader for #{state.lattice_prefix}",
          ack_policy: "none",
          filter_subject: ">",
          deliver_policy: "last_per_subject",
          deliver_subject: state.metadata_deliver_subject,
          max_ack_pending: -1,
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
        handle_consumer_create_response("metadata", body |> Jason.decode!())

      {:error, :no_responders} ->
        Logger.error(
          "No responders to attempt to create JS consumer. Is JetStream enabled/configured properly?"
        )

      {:error, :timeout} ->
        Logger.error(
          "Failed to receive create consumer ACK from JetStream within timeout. Ensure JetStream is enabled on your NATS server."
        )
    end

    {:noreply, state, {:continue, :create_legacy_eph_consumer}}
  end

  @impl true
  def handle_continue(:create_legacy_eph_consumer, state) do
    stream_name = "LATTICECACHE_#{state.lattice_prefix}"

    if stream_exists?(state.lattice_prefix, stream_name, state.domain) do
      Logger.warn(
        "Detected deprecated lattice cache stream #{stream_name}. Reading data from this, but will not write new data"
      )

      Logger.warn("It is strongly recommended that you delete this stream immediately")

      consumer_name = String.replace(state.legacy_deliver_subject, "_INBOX.", "")

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
            description: "legacy cache loader for #{state.lattice_prefix}",
            ack_policy: "explicit",
            filter_subject: ">",
            deliver_policy: "last_per_subject",
            deliver_subject: state.legacy_deliver_subject,
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
          handle_consumer_create_response("legacy", body |> Jason.decode!())

        {:error, :no_responders} ->
          Logger.error(
            "No responders to attempt to create JS consumer. Is JetStream enabled/configured properly?"
          )

        {:error, :timeout} ->
          Logger.error(
            "Failed to receive create consumer ACK from JetStream within timeout. Ensure JetStream is enabled on your NATS server."
          )
      end
    end

    {:noreply, state}
  end

  def kv_put(lattice_prefix, "", key, value), do: kv_put(lattice_prefix, nil, key, value)

  def kv_put(lattice_prefix, js_domain, key, value) do
    topic =
      if js_domain == nil do
        "$KV.WCMDCACHE_#{lattice_prefix}.#{key}"
      else
        "#{js_domain}.$KV.WCMDCACHE_#{lattice_prefix}.#{key}"
      end

    case HostCore.Nats.safe_req(HostCore.Nats.control_connection(lattice_prefix), topic, value) do
      {:ok, _msg} ->
        Logger.debug("Put metadata in lattice bucket #{lattice_prefix}, key #{key}")

      {:error, :no_responders} ->
        Logger.error(
          "Failed to put metadata in lattice bucket #{lattice_prefix}, key #{key}: No responders"
        )

      {:error, :timeout} ->
        Logger.error(
          "Failed to put metadata in lattice bucket #{lattice_prefix}, key #{key}: Timeout"
        )
    end

    :ok
  end

  def delete_kv_bucket(lattice_prefix, js_domain) do
    del_topic =
      if js_domain == nil do
        "$JS.API.STREAM.DELETE.KV_WCMDCACHE_#{lattice_prefix}"
      else
        "$JS.#{js_domain}.API.STREAM.DELETE.KV_WCMDCACHE_#{lattice_prefix}"
      end

    HostCore.Nats.safe_req(
      HostCore.Nats.control_connection(lattice_prefix),
      del_topic,
      <<>>
    )
  end

  defp stream_exists?(lattice_prefix, stream_name, ""),
    do: stream_exists?(lattice_prefix, stream_name, nil)

  defp stream_exists?(lattice_prefix, stream_name, js_domain) do
    info_topic =
      if js_domain == nil do
        "$JS.API.STREAM.INFO.#{stream_name}"
      else
        "$JS.#{js_domain}.API.STREAM.INFO.#{stream_name}"
      end

    with {:ok, %{body: body}} <-
           HostCore.Nats.safe_req(
             HostCore.Nats.control_connection(lattice_prefix),
             info_topic,
             <<>>
           ),
         {:ok, decoded} <- Jason.decode(body) do
      Map.has_key?(decoded, "config")
    else
      {:error, e} ->
        Logger.error("Failed to check stream existence: #{inspect(e)}")
        false
    end
  end

  defp handle_consumer_create_response(
         label,
         %{
           "type" => "io.nats.jetstream.api.v1.consumer_create_response",
           "error" => %{
             "code" => code,
             "description" => desc
           }
         }
       ) do
    Logger.error("Failed to create #{label} ephemeral cache loader consumer (#{code}) - #{desc}")
  end

  defp handle_consumer_create_response(
         label,
         %{
           "type" => "io.nats.jetstream.api.v1.consumer_create_response",
           "config" => _config
         }
       ) do
    Logger.info("Created #{label} ephemeral consumer for lattice cache loader")
  end

  defp handle_stream_create_response(%{
         "type" => "io.nats.jetstream.api.v1.stream_create_response",
         "config" => _config,
         "state" => state
       }) do
    Logger.info(
      "Lattice metadata cache created or verified as existing (#{state["consumer_count"]} consumers)."
    )
  end

  defp handle_stream_create_response(%{
         "type" => "io.nats.jetstream.api.v1.stream_create_response",
         "error" => %{
           "code" => 500,
           "description" => "stream name already in use"
         }
       }) do
    Logger.info(
      "Lattice metadata cache name already in use, assuming previously-configured stream"
    )
  end

  # This is almost identical to above, but for some reason when the stream has multiple replicas,
  # this returns a 400 error code rather than 500
  defp handle_stream_create_response(%{
         "type" => "io.nats.jetstream.api.v1.stream_create_response",
         "error" => %{
           "code" => 400,
           "description" => "stream name already in use"
         }
       }) do
    Logger.info(
      "Lattice metadata cache name already in use, assuming previously-configured stream"
    )
  end

  defp handle_stream_create_response(%{
         "type" => "io.nats.jetstream.api.v1.stream_create_response",
         "error" => %{
           "code" => 400,
           "description" => "stream name already in use with a different configuration"
         }
       }) do
    Logger.info(
      "Lattice metadata cache name already in use with different configuration, using previously-configured stream"
    )
  end

  defp handle_stream_create_response(%{
         "error" => %{
           "code" => 500,
           "description" => "subjects overlap with an existing stream"
         },
         "type" => "io.nats.jetstream.api.v1.stream_create_response"
       }) do
    Logger.info(
      "Lattice metadata cache subjects already configured, assuming previously-configured stream"
    )
  end

  defp handle_stream_create_response(body) do
    Logger.warn(
      "Received unexpected response from NATS when attempting to create metadata cache: #{inspect(body)}"
    )
  end
end
