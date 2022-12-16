defmodule HostCore.ConfigServiceClient do
  @moduledoc """
  This module is a client that consumes a configuration service over the appropriate configuration service topic. All configuration
  service calls occur over NATS and the topic can be overridden in virtual host configuration
  """
  require Logger

  def request_configuration(lattice_prefix, labels, topic)
      when is_binary(topic) do
    topic = "#{topic}.req"

    payload =
      Jason.encode!(%{
        labels: labels
      })

    with {:ok, message} <- api_request(lattice_prefix, topic, payload),
         {:ok, decoded} <- Jason.decode(message.body) do
      {:ok, decoded}
    else
      {:error, e} ->
        {:error, "Failed to make config service request: #{inspect(e)}"}
    end
  end

  defp api_request(prefix, topic, payload, timeout \\ 2_000) do
    prefix
    |> HostCore.Nats.control_connection()
    |> HostCore.Nats.safe_req(topic, payload, receive_timeout: timeout)
  end
end
