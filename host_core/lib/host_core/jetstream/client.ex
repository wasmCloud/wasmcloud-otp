defmodule HostCore.Jetstream.Client do
  @moduledoc false
  use GenServer

  @kvoperation "KV-Operation"
  @kvpurge "PURGE"

  alias HostCore.Jetstream.LegacyCacheLoader

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

  # Ensure that the metadata cache key-value bucket exists, creating a default one if it does not
  @impl true
  def handle_continue(:ensure_stream, state) do
    for _i <- 0..3 do
      if state.lattice_prefix
         |> HostCore.Nats.control_connection()
         |> Process.whereis()
         |> is_nil() do
        Process.sleep(200)
      end
    end

    create_topic = create_bucket_topic(state.lattice_prefix, state.domain)
    stream_topic = kv_stream_topic(state.lattice_prefix)

    payload_json =
      Jason.encode!(%{
        name: "KV_LATTICEDATA_#{state.lattice_prefix}",
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
      })

    case state.lattice_prefix
         |> HostCore.Nats.control_connection()
         |> HostCore.Nats.safe_req(create_topic, payload_json) do
      {:ok, %{body: body}} ->
        handle_stream_create_response(Jason.decode!(body))

      {:error, :no_responders} ->
        Logger.error("No responders to create stream. Is JetStream enabled/configured properly?")

      {:error, :timeout} ->
        Logger.error(
          "Failed to receive create stream ACK from JetStream within timeout. Is JetStream enabled?"
        )
    end

    {:noreply, state, {:continue, :create_eph_consumer}}
  end

  # Create an ephemeral consumer on long-lived subscription listening for key changes on the metadata cache
  @impl true
  def handle_continue(:create_eph_consumer, state) do
    Logger.info("Attempting to create ephemeral consumer (metadata loader)",
      js_domain: state.domain
    )

    stream_name = "KV_LATTICEDATA_#{state.lattice_prefix}"
    consumer_name = String.replace(state.metadata_deliver_subject, "_INBOX.", "")

    create_topic = create_consumer_topic(stream_name, state.domain)

    payload_json =
      Jason.encode!(%{
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
      })

    case state.lattice_prefix
         |> HostCore.Nats.control_connection()
         |> HostCore.Nats.safe_req(create_topic, payload_json) do
      {:ok, %{body: body}} ->
        handle_consumer_create_response("metadata", Jason.decode!(body))

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

  # Creates an ephemeral consumer against the legacy LATTICECACHE_{prefix} if such a stream exists. This will
  # migrate all the data from that stream into the new metadata cache and then delete it.
  @impl true
  def handle_continue(:create_legacy_eph_consumer, state) do
    stream_name = "LATTICECACHE_#{state.lattice_prefix}"

    if stream_exists?(state.lattice_prefix, stream_name, state.domain) do
      Logger.warn("Detected deprecated lattice cache stream #{stream_name}.")

      Logger.warn(
        "The LATTICECACHE_#{state.lattice_prefix} stream will be removed. You should not start actors, providers, or add metadata from older hosts relying on that stream."
      )

      consumer_name = String.replace(state.legacy_deliver_subject, "_INBOX.", "")

      create_topic = create_consumer_topic(stream_name, state.domain)

      payload_json =
        Jason.encode!(%{
          stream_name: stream_name,
          name: consumer_name,
          config: %{
            description: "legacy cache loader for #{state.lattice_prefix}",
            ack_policy: "explicit",
            filter_subject: ">",
            deliver_policy: "last_per_subject",
            deliver_subject: state.legacy_deliver_subject,
            max_ack_pending: 20_000,
            max_deliver: -11,
            replay_policy: "instant"
          }
        })

      conn = HostCore.Nats.control_connection(state.lattice_prefix)

      # Create a subscriber pointing at self() that we'll deal with using receive, that pulls
      # each piece of data from the old cache and writes it to the new one
      with {:ok, sub} <- Gnat.sub(conn, self(), state.legacy_deliver_subject),
           {:ok, %{body: body}} <- HostCore.Nats.safe_req(conn, create_topic, payload_json),
           {:ok, decoded} <- Jason.decode(body) do
        if Map.has_key?(decoded, "config") do
          # consumer created for stream
          Logger.warn("Migrating data from legacy lattice cache to new key-value store")
          migrate_bucket_keys(state.domain)
          Gnat.unsub(conn, sub)

          delete_stream(
            "LATTICECACHE_#{state.lattice_prefix}",
            state.lattice_prefix,
            state.domain
          )
        end
      else
        _ ->
          Logger.warn("Skipping data migration from legacy cache")
      end
    end

    {:noreply, state}
  end

  def kv_del(lattice_prefix, "", key), do: kv_del(lattice_prefix, nil, key)

  def kv_del(lattice_prefix, js_domain, key) do
    # delete requires us to make a request on the topic with headers
    # KV-Operation : PURGE
    topic = kv_operation_topic(lattice_prefix, key, js_domain)
    headers = [{@kvoperation, @kvpurge}]

    # TODO: once the Jetstream hex package support js_domains, switch this
    # code to use JetStream.API.xxxx
    case lattice_prefix
         |> HostCore.Nats.control_connection()
         |> Gnat.request(topic, <<>>, headers: headers) do
      {:ok, _} ->
        Logger.debug("Deleted key #{key} from metadata lattice bucket #{lattice_prefix}")
        :ok

      {:error, e} ->
        Logger.error(
          "Failed to delete key #{key} from metadata bucket #{lattice_prefix}: #{inspect(e)}"
        )

        {:error, e}
    end
  end

  # Make sure that where applicable `value` is already encoded as JSON because this function won't do it.
  def kv_put(lattice_prefix, "", key, value), do: kv_put(lattice_prefix, nil, key, value)

  def kv_put(lattice_prefix, js_domain, key, value) do
    topic = kv_operation_topic(lattice_prefix, key, js_domain)

    case lattice_prefix
         |> HostCore.Nats.control_connection()
         |> HostCore.Nats.safe_req(topic, value) do
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
    stream_name = "KV_LATTICEDATA_#{lattice_prefix}"
    delete_stream(stream_name, lattice_prefix, js_domain)
  end

  def delete_stream(stream_name, lattice_prefix, js_domain) do
    del_topic = stream_delete_topic(stream_name, js_domain)

    lattice_prefix
    |> HostCore.Nats.control_connection()
    |> HostCore.Nats.safe_req(del_topic, <<>>)
  end

  def ensure_linkdef_id(linkdef) do
    if Map.has_key?(linkdef, :id) do
      linkdef
    else
      Map.put(
        linkdef,
        :id,
        linkdef_hash(linkdef.actor_id, linkdef.contract_id, linkdef.link_name)
      )
    end
  end

  def linkdef_hash(actor_id, contract_id, link_name) do
    sha = :crypto.hash_init(:sha256)
    sha = :crypto.hash_update(sha, actor_id)
    sha = :crypto.hash_update(sha, contract_id)
    sha = :crypto.hash_update(sha, link_name)
    sha_binary = :crypto.hash_final(sha)
    sha_binary |> Base.encode16() |> String.upcase()
  end

  defp create_bucket_topic(lattice_prefix, nil),
    do: "$JS.API.STREAM.CREATE.KV_LATTICEDATA_#{lattice_prefix}"

  defp create_bucket_topic(lattice_prefix, js_domain) when is_binary(js_domain),
    do: "$JS.#{js_domain}.API.STREAM.CREATE.KV_LATTICEDATA_#{lattice_prefix}"

  defp kv_stream_topic(lattice_prefix), do: "$KV.LATTICEDATA_#{lattice_prefix}.>"

  defp create_consumer_topic(stream_name, nil), do: "$JS.API.CONSUMER.CREATE.#{stream_name}"

  defp create_consumer_topic(stream_name, js_domain) when is_binary(js_domain),
    do: "$JS.#{js_domain}.API.CONSUMER.CREATE.#{stream_name}"

  defp kv_operation_topic(lattice_prefix, key, nil),
    do: "$KV.LATTICEDATA_#{lattice_prefix}.#{key}"

  defp kv_operation_topic(lattice_prefix, key, js_domain) when is_binary(js_domain),
    do: "$JS.#{js_domain}.API.$KV.LATTICEDATA_#{lattice_prefix}.#{key}"

  defp stream_delete_topic(stream_name, nil), do: "$JS.API.STREAM.DELETE.#{stream_name}"

  defp stream_delete_topic(stream_name, js_domain) when is_binary(js_domain),
    do: "$JS.#{js_domain}.API.STREAM.DELETE.#{stream_name}"

  # a receive loop that will drop out if no new message is received within 200ms, which is
  # an indicator that no more data is forthcoming from the legacy cache. We need the js_domain
  # here to ensure the KV bucket put goes to the right place
  defp migrate_bucket_keys(js_domain) do
    receive do
      {:msg, %{topic: topic, body: body}} ->
        LegacyCacheLoader.handle_legacy_request(js_domain, topic, body)
        migrate_bucket_keys(js_domain)
    after
      200 ->
        Logger.debug("Finished reading data from legacy lattice cache")
    end
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
           lattice_prefix
           |> HostCore.Nats.control_connection()
           |> HostCore.Nats.safe_req(info_topic, <<>>),
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
