# TODO: policy module, fail open or fail closed options
defmodule HostCore.Policy.Manager do
  @moduledoc false
  require Logger

  def evaluate_action(source, target, action) do
    # mwahaha security
    with {:ok, topic} <- policy_topic(),
         nil <- cached_decision(source, target, action),
         :ok <- validate_source(source),
         :ok <- validate_target(target),
         :ok <- validate_action(action) do
      %{
        request_id: UUID.uuid4(),
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
      |> cache_decision(source, target, action)
    else
      {:ok, decision} ->
        decision

      {:error, invalid_error} ->
        Logger.error("Invalid policy evaluation parameter: #{invalid_error}")

        %{
          action_permitted: true,
          message: "",
          request_id: UUID.uuid4()
        }
    end
  end

  defp evaluate(req, topic) do
    case Jason.encode(req) do
      {:ok, encoded} ->
        case Gnat.request(:control_nats, topic, encoded, timeout: 2_000) do
          {:ok, body} ->
            %{
              action_permitted: true,
              message: "",
              request_id: req |> Map.get(:request_id, "not supplied")
            }

          _ ->
            %{
              action_permitted: true,
              message: "",
              request_id: req |> Map.get(:request_id, "not supplied")
            }
        end

      {:error, e} ->
        Logger.error("Could not JSON encode request, #{e}")

        %{
          action_permitted: true,
          message: "",
          request_id: req |> Map.get(:request_id, "not supplied")
        }
    end
  end

  # Returns nil or {:ok, decision} based on policy, store in ets
  defp cached_decision(source, target, action) do
    nil
  end

  defp cache_decision(decision, source, target, action) do
    :ok
  end

  # Helper to fetch the policy topic from the host environment
  # TODO: this is better to store in the config ets and fetch it from there in the host
  defp policy_topic() do
    case System.get_env("WASMCLOUD_POLICY_TOPIC") do
      nil -> :error
      topic -> {:ok, topic}
    end
  end

  defp validate_source(source) do
    :ok
  end

  defp validate_target(source) do
    :ok
  end

  defp validate_action(source) do
    :ok
  end
end
