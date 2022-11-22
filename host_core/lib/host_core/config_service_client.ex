defmodule HostCore.ConfigServiceClient do
  require Logger

  def request_configuration(lattice_prefix, labels, topic)
      when is_binary(topic) do
    topic = "#{topic}.req"

    payload =
      %{
        labels: labels
      }
      |> Jason.encode!()

    with {:ok, message} <- api_request(lattice_prefix, topic, payload),
         {:ok, decoded} <- Jason.decode(message.body) do
      {:ok, decoded}
    else
      {:error, e} ->
        {:error, "Failed to make config service request: #{inspect(e)}"}
    end
  end

  defp api_request(prefix, topic, payload, timeout \\ 2_000) do
    HostCore.Nats.safe_req(
      HostCore.Nats.control_connection(prefix),
      topic,
      payload,
      receive_timeout: timeout
    )
  end
end
