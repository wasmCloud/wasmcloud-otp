defmodule WasmcloudHost.Lattice.ControlInterface do
  @wasmbus_prefix "wasmbus.ctl."

  def start_actor(actor_ociref, _replicas, host_id) do
    payload = Jason.encode!(%{"actor_ref" => actor_ociref, "host_id" => host_id})
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.cmd.#{host_id}.la"

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :timeout} ->
        {:error, :timeout}
    end
  end

  defp auction_actor(actor_ociref, _constraints) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.auction.actor"
  end

  defp ctl_request(topic, payload, timeout) do
    Gnat.request(:control_nats, topic, payload, request_timeout: timeout)
  end
end
