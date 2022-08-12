defmodule HostCore.Policy.Manager do
  @moduledoc false
  require Logger
  use Gnat.Server

  @policy_table :policy_table

  def request(%{
        body: body,
        reply_to: _reply_to,
        topic: _topic
      }) do
    case Jason.decode(body, keys: :atoms!) do
      {:ok, %{request_id: request_id, permitted: permitted, message: message}} ->
        override_decision(request_id, permitted, message)
        {:reply, Jason.encode!(%{success: true})}

      msg ->
        IO.inspect(msg)
        IO.inspect(body)
        {:reply, Jason.encode!(%{success: false})}
    end
  end

  def spec() do
    case System.get_env("WASMCLOUD_POLICY_CHANGES_TOPIC") do
      nil ->
        []

      topic ->
        cs_settings = %{
          connection_name: :control_nats,
          module: __MODULE__,
          subscription_topics: [
            %{topic: topic}
          ]
        }

        [
          Supervisor.child_spec(
            {Gnat.ConsumerSupervisor, cs_settings},
            id: :policy_manager
          )
        ]
    end
  end

  def evaluate_action(source, target, action) do
    with {:ok, topic} <- HostCore.Policy.Manager.policy_topic(),
         nil <- cached_decision(source, target, action),
         :ok <- validate_source(source),
         :ok <- validate_target(target),
         :ok <- validate_action(action) do
      request_id = UUID.uuid4()

      %{
        request_id: request_id,
        source: source,
        target: target,
        action: action,
        host: %{
          public_key: HostCore.Host.host_key(),
          lattice_id: HostCore.Host.lattice_prefix(),
          labels: HostCore.Host.host_labels(),
          valid_cluster_issuers: HostCore.Host.cluster_issuers()
        }
      }
      |> evaluate(topic)
      |> cache_decision(source, target, action, request_id)
    else
      :policy_eval_disabled ->
        allowed_action("Policy evaluation disabled, allowing action", "")

      {:ok, decision} ->
        decision

      {:error, invalid_error} ->
        Logger.error("#{invalid_error}")

        allowed_action(invalid_error)
    end
  end

  defp evaluate(req, topic) do
    case Jason.encode(req) do
      {:ok, encoded} ->
        case HostCore.Nats.safe_req(:control_nats, topic, encoded,
               receive_timeout: HostCore.Policy.Manager.policy_timeout()
             ) do
          {:ok, %{body: body}} ->
            # Decode body with existing atom keys
            case Jason.decode(body, keys: :atoms!) do
              {:ok, policy_res} ->
                policy_res

              {:error, _decode} ->
                allowed_action(
                  "Policy response failed to decode, allowing",
                  req |> Map.get(:request_id, "not supplied")
                )
            end

          {:error, :timeout} ->
            allowed_action(
              "Policy request timed out, allowing action",
              req |> Map.get(:request_id, "not supplied")
            )
        end

      {:error, e} ->
        Logger.error("Could not JSON encode request, #{e}")

        allowed_action("", req |> Map.get(:request_id, "not supplied"))
    end
  end

  # Returns nil if not present or {:ok, decision} based on previous policy decision
  defp cached_decision(source, target, action) do
    case :ets.lookup(@policy_table, {source, target, action}) do
      [{{_src, _tgt, _act}, decision}] -> {:ok, decision}
      [] -> nil
    end
  end

  # Inserts a policy decision into the policy table as a nested tuple. This
  # allows future lookups to easily fetch decision based on {source,target,action}
  # Also stores the {source,target,action} under the request ID as a key for O(1) lookups
  # to invalidate
  defp cache_decision(decision, source, target, action, request_id) do
    :ets.insert(@policy_table, {{source, target, action}, decision})
    :ets.insert(@policy_table, {request_id, {source, target, action}})
    decision
  end

  # Lookup the decision by request ID, then delete both from the policy table
  defp override_decision(request_id, permitted, message) do
    case :ets.lookup(@policy_table, request_id) do
      [{_request_id, {source, target, action}}] ->
        :ets.insert(
          @policy_table,
          {{source, target, action},
           %{
             permitted: permitted,
             message: message,
             request_id: request_id
           }}
        )

      [] ->
        nil
    end
  end

  ##
  # Basic validation of source, target, and action ensuring required fields are present
  ##
  defp validate_source(%{
         public_key: _public_key,
         capabilities: _caps,
         issuer: _issuer,
         issued_on: _issued_on,
         expires_in_mins: _expires
       }) do
    :ok
  end

  defp validate_source(source) when is_map(source) do
    # Narrow down missing fields by removing present fields from the list
    missing_fields =
      [:public_key, :capabilities, :issuer, :issued_on, :expires_in_mins]
      |> Enum.reject(fn required_field -> Map.get(source, required_field) != nil end)
      |> Enum.join(", ")

    {:error, "Invalid source argument, missing required fields: #{missing_fields}"}
  end

  defp validate_source(_), do: {:error, "Invalid source argument, source was not a map"}

  defp validate_target(%{
         public_key: _public_key,
         issuer: _issuer
       }) do
    :ok
  end

  defp validate_target(target) when is_map(target) do
    # Narrow down missing fields by removing present fields from the list
    missing_fields =
      [:public_key, :issuer]
      |> Enum.reject(fn required_field -> Map.get(target, required_field) != nil end)
      |> Enum.join(", ")

    {:error, "Invalid target argument, missing required fields: #{missing_fields}"}
  end

  defp validate_target(_), do: {:error, "Invalid target argument, target was not a map"}

  # Ensure action is a string
  defp validate_action(action) when is_binary(action), do: :ok
  defp validate_action(_), do: {:error, "Invalid action argument, action was not a string"}

  # Helper constructor for an allowed action structure
  defp allowed_action(message, request_id \\ UUID.uuid4()) do
    %{
      permitted: true,
      message: message,
      request_id: request_id
    }
  end

  def policy_topic() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> {:ok, config_map[:policy_topic]}
      _ -> :policy_eval_disabled
    end
  end

  def policy_timeout() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:policy_timeout]
      _ -> 1_000
    end
  end
end
