defmodule HostCore.Policy.Manager do
  @moduledoc false
  require Logger

  alias HostCore.Policy.Manager

  use Gnat.Server

  @policy_table :policy_table
  # Deny actions by default
  @default_permit false

  def request(%{
        body: body,
        reply_to: _reply_to,
        topic: _topic
      }) do
    case Jason.decode(body, keys: :atoms!) do
      {:ok, %{request_id: request_id, permitted: permitted, message: message}} ->
        override_decision(request_id, permitted, message)
        {:reply, Jason.encode!(%{success: true})}

      _ ->
        {:reply, Jason.encode!(%{success: false})}
    end
  end

  def spec(lattice_prefix) do
    case get_policy_change_topic(lattice_prefix) do
      nil ->
        []

      topic ->
        cs_settings = %{
          connection_name: HostCore.Nats.control_connection(lattice_prefix),
          module: __MODULE__,
          subscription_topics: [
            %{topic: topic}
          ]
        }

        [
          Supervisor.child_spec(
            {Gnat.ConsumerSupervisor, cs_settings},
            id: String.to_atom("polman-#{lattice_prefix}")
          )
        ]
    end
  end

  @spec evaluate_action(
          host_config :: HostCore.Vhost.Configuration.t(),
          labels :: map(),
          source :: map(),
          target :: map(),
          action :: String.t()
        ) :: map()
  def evaluate_action(host_config, labels, source, target, action) do
    with {:ok, topic} <- Manager.policy_topic(host_config),
         nil <- cached_decision(source, target, action, host_config.lattice_prefix),
         :ok <- validate_source(source),
         :ok <- validate_target(target),
         :ok <- validate_action(action) do
      request_id = UUID.uuid4()

      %{
        requestId: request_id,
        source: source,
        target: target,
        action: action,
        host: %{
          publicKey: host_config.host_key,
          issuer: host_config.cluster_key,
          latticeId: host_config.lattice_prefix,
          labels: labels,
          clusterIssuers: host_config.cluster_issuers
        }
      }
      |> evaluate(topic, host_config)
      |> cache_decision(source, target, action, host_config.lattice_prefix, request_id)
    else
      :policy_eval_disabled ->
        allowed_action("Policy evaluation disabled, allowing action", "")

      {:ok, decision} ->
        decision

      {:error, invalid_error} ->
        Logger.error("#{invalid_error}")

        default_decision(invalid_error, "")
    end
  end

  defp get_policy_change_topic(lattice_prefix) do
    System.get_env("WASMCLOUD_POLICY_CHANGES_TOPIC_#{String.replace(lattice_prefix, "-", "_")}") ||
      System.get_env("WASMCLOUD_POLICY_CHANGES_TOPIC")
  end

  defp evaluate(req, topic, host_config) do
    case Jason.encode(req) do
      {:ok, encoded} ->
        case host_config.lattice_prefix
             |> HostCore.Nats.control_connection()
             |> HostCore.Nats.safe_req(topic, encoded,
               receive_timeout: Manager.policy_timeout(host_config)
             ) do
          {:ok, %{body: body}} ->
            # Decode body with existing atom keys
            case Jason.decode(body, keys: :atoms!) do
              {:ok, policy_res} ->
                {policy_res, true}

              {:error, _decode} ->
                {default_decision(
                   "Policy response failed to decode",
                   Map.get(req, :requestId, "not supplied")
                 ), false}
            end

          {:error, :no_responders} ->
            {default_decision(
               "No responders to policy request (policy server not listening?)",
               Map.get(req, :requestId, "not supplied")
             ), false}

          {:error, :timeout} ->
            {default_decision(
               "Policy request timed out",
               Map.get(req, :requestId, "not supplied")
             ), false}
        end

      {:error, e} ->
        Logger.error("Could not JSON encode request, #{e}")

        {default_decision("", Map.get(req, :requestId, "not supplied")), false}
    end
  end

  # Returns nil if not present or {:ok, decision} based on previous policy decision
  defp cached_decision(source, target, action, lattice_prefix) do
    case :ets.lookup(@policy_table, {source, target, action, lattice_prefix}) do
      [{{_src, _tgt, _act, _prefix}, decision}] -> {:ok, decision}
      [] -> nil
    end
  end

  defp cache_decision({decision, false}, _source, _target, _action, _prefix, _request_id),
    do: decision

  # Inserts a policy decision into the policy table as a nested tuple. This
  # allows future lookups to easily fetch decision based on {source,target,action}
  # Also stores the {source,target,action} under the request ID as a key for O(1) lookups
  # to invalidate
  defp cache_decision({decision, true}, source, target, action, prefix, request_id) do
    :ets.insert(@policy_table, {{source, target, action, prefix}, decision})
    :ets.insert(@policy_table, {request_id, {source, target, action, prefix}})
    decision
  end

  # Lookup the decision by request ID, then delete both from the policy table
  defp override_decision(request_id, permitted, message) do
    case :ets.lookup(@policy_table, request_id) do
      [{_request_id, {source, target, action, prefix}}] ->
        :ets.insert(
          @policy_table,
          {{source, target, action, prefix},
           %{
             permitted: permitted,
             message: message,
             requestId: request_id
           }}
        )

      [] ->
        nil
    end
  end

  @spec default_source() :: map()
  def default_source() do
    %{
      publicKey: "",
      contractId: "",
      linkName: "",
      capabilities: [],
      issuer: "",
      issuedOn: "",
      expiresAt: DateTime.utc_now() |> DateTime.add(60) |> DateTime.to_unix(),
      expired: false
    }
  end

  ##
  # Basic validation of source, target, and action ensuring required fields are present
  ##
  defp validate_source(%{
         publicKey: _public_key,
         capabilities: _caps,
         issuer: _issuer,
         issuedOn: _issued_on,
         expired: _expired,
         expiresAt: _expires_at
       }) do
    :ok
  end

  defp validate_source(source) when is_map(source) do
    # Narrow down missing fields by removing present fields from the list
    missing_fields =
      [:publicKey, :capabilities, :issuer, :issuedOn, :expired, :expiresAt]
      |> Enum.filter(fn required_field -> Map.get(source, required_field) == nil end)
      |> Enum.join(", ")

    {:error, "Invalid source argument, missing required fields: #{missing_fields}"}
  end

  defp validate_source(_), do: {:error, "Invalid source argument, source was not a map"}

  defp validate_target(%{
         publicKey: _public_key,
         issuer: _issuer
       }) do
    :ok
  end

  defp validate_target(target) when is_map(target) do
    # Narrow down missing fields by removing present fields from the list
    missing_fields =
      [:publicKey, :issuer]
      |> Enum.reject(fn required_field -> Map.get(target, required_field) != nil end)
      |> Enum.join(", ")

    {:error, "Invalid target argument, missing required fields: #{missing_fields}"}
  end

  defp validate_target(_), do: {:error, "Invalid target argument, target was not a map"}

  # Ensure action is a string
  defp validate_action(action) when is_binary(action), do: :ok
  defp validate_action(_), do: {:error, "Invalid action argument, action was not a string"}

  # Helper constructor for an allowed action structure
  defp allowed_action(message, request_id) do
    %{
      permitted: true,
      message: message,
      requestId: request_id
    }
  end

  # Helper constructor for a "default" decision
  defp default_decision(message, request_id) do
    %{
      permitted: @default_permit,
      message: message,
      requestId: request_id
    }
  end

  def policy_topic(config) do
    if config.policy_topic == nil || config.policy_topic == "" do
      :policy_eval_disabled
    else
      {:ok, config.policy_topic}
    end
  end

  def policy_timeout(config) do
    config.policy_timeout_ms || 1_000
  end
end
