defmodule WasmcloudHost.Lattice.ControlInterface do
  @wasmbus_prefix "wasmbus.ctl."

  def scale_actor(actor_id, actor_ref, desired_replicas, host_id) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.cmd.#{host_id}.scale"

    payload =
      Jason.encode!(%{
        "actor_id" => actor_id,
        "actor_ref" => actor_ref,
        "replicas" => desired_replicas
      })

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :timeout} ->
        {:error, "Request to start actor timed out"}
    end
  end

  def start_provider(provider_ociref, link_name, host_id) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.cmd.#{host_id}.lp"

    payload =
      Jason.encode!(%{
        "provider_ref" => provider_ociref,
        "link_name" => link_name
      })

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :timeout} ->
        {:error, "Request to start provider timed out"}
    end
  end

  def stop_provider(provider_id, link_name, host_id) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.cmd.#{host_id}.sp"

    payload =
      Jason.encode!(%{
        "provider_ref" => provider_id,
        "link_name" => link_name
      })

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :timeout} ->
        {:error, "Request to stop provider timed out"}
    end
  end

  def auction_actor(actor_ociref, _constraints) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.auction.actor"

    payload =
      Jason.encode!(%{
        "constraints" => %{},
        "actor_ref" => actor_ociref
      })

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)
        host_id = Map.get(resp, "host_id", nil)

        if host_id != nil do
          {:ok, host_id}
        else
          {:error, "Auction response did not contain Host ID"}
        end

      {:error, :timeout} ->
        {:error, "Auction request timed out, no suitable hosts found"}
    end
  end

  def auction_provider(provider_ociref, link_name, _constraints) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.auction.provider"

    payload =
      Jason.encode!(%{
        "constraints" => %{},
        "provider_ref" => provider_ociref,
        "link_name" => link_name
      })

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)
        host_id = Map.get(resp, "host_id", nil)

        if host_id != nil do
          {:ok, host_id}
        else
          {:error, "Auction response did not contain Host ID"}
        end

      {:error, :timeout} ->
        {:error, "Auction request timed out, no suitable hosts found"}
    end
  end

  def put_linkdef(
        actor_id,
        contract_id,
        link_name,
        provider_id,
        values
      ) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.linkdefs.put"

    payload =
      Jason.encode!(%{
        "actor_id" => actor_id,
        "contract_id" => contract_id,
        "link_name" => link_name,
        "provider_id" => provider_id,
        "values" => values
      })

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :timeout} ->
        {:error, "Request to stop provider timed out"}
    end
  end

  def delete_linkdef(actor_id, contract_id, link_name) do
    topic = "#{@wasmbus_prefix}#{HostCore.Host.lattice_prefix()}.linkdefs.del"

    payload =
      Jason.encode!(%{
        "actor_id" => actor_id,
        "contract_id" => contract_id,
        "link_name" => link_name
      })

    case ctl_request(topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :timeout} ->
        {:error, "Request to stop provider timed out"}
    end
  end

  defp ctl_request(topic, payload, timeout) do
    Gnat.request(:control_nats, topic, payload, request_timeout: timeout)
  end
end
