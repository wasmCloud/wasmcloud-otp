defmodule WasmcloudHost.Lattice.ControlInterface do
  @wasmbus_prefix "wasmbus.ctl."

  def scale_actor(actor_id, actor_ref, desired_count, host_id) do
    {_pk, _pid, prefix} = WasmcloudHost.Application.first_host()

    topic = "#{@wasmbus_prefix}#{prefix}.cmd.#{host_id}.scale"

    payload =
      Jason.encode!(%{
        "actor_id" => actor_id,
        "actor_ref" => actor_ref,
        "count" => desired_count
      })

    case ctl_request(prefix, topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :no_responders} ->
        {:error, "No responders to actor start request"}

      {:error, :timeout} ->
        {:error, "Request to start actor timed out"}
    end
  end

  def start_provider(provider_ociref, link_name, host_id, provider_configuration \\ "") do
    {_pk, _pid, prefix} = WasmcloudHost.Application.first_host()

    topic = "#{@wasmbus_prefix}#{prefix}.cmd.#{host_id}.lp"

    payload =
      Jason.encode!(%{
        "provider_ref" => provider_ociref,
        "link_name" => link_name,
        "configuration" => provider_configuration
      })

    case ctl_request(prefix, topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :no_responders} ->
        {:error, "No responders to start provider request"}

      {:error, :timeout} ->
        {:error, "Request to start provider timed out"}
    end
  end

  def stop_provider(provider_id, link_name, host_id) do
    {_pk, _pid, prefix} = WasmcloudHost.Application.first_host()

    topic = "#{@wasmbus_prefix}#{prefix}.cmd.#{host_id}.sp"

    payload =
      Jason.encode!(%{
        "provider_ref" => provider_id,
        "link_name" => link_name
      })

    case ctl_request(prefix, topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :no_responders} ->
        {:error, "No responders to stop provider request"}

      {:error, :timeout} ->
        {:error, "Request to stop provider timed out"}
    end
  end

  def auction_actor(actor_ociref, _constraints) do
    {_pk, _pid, prefix} = WasmcloudHost.Application.first_host()

    topic = "#{@wasmbus_prefix}#{prefix}.auction.actor"

    payload =
      Jason.encode!(%{
        "constraints" => %{},
        "actor_ref" => actor_ociref
      })

    case ctl_request(prefix, topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)
        host_id = Map.get(resp, "host_id", nil)

        if host_id != nil do
          {:ok, host_id}
        else
          {:error, "Auction response did not contain Host ID"}
        end

      {:error, :no_responders} ->
        {:error, "No responders to actor auction"}

      {:error, :timeout} ->
        {:error, "Auction request timed out, no suitable hosts found"}
    end
  end

  def auction_provider(provider_ociref, link_name, _constraints) do
    {_pk, _pid, prefix} = WasmcloudHost.Application.first_host()

    topic = "#{@wasmbus_prefix}#{prefix}.auction.provider"

    payload =
      Jason.encode!(%{
        "constraints" => %{},
        "provider_ref" => provider_ociref,
        "link_name" => link_name
      })

    case ctl_request(prefix, topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)
        host_id = Map.get(resp, "host_id", nil)

        if host_id != nil do
          {:ok, host_id}
        else
          {:error, "Auction response did not contain Host ID"}
        end

      {:error, :no_responders} ->
        {:error, "No responders to provider auction"}

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
    {_pk, _pid, prefix} = WasmcloudHost.Application.first_host()

    topic = "#{@wasmbus_prefix}#{prefix}.linkdefs.put"

    payload =
      Jason.encode!(%{
        "actor_id" => actor_id,
        "contract_id" => contract_id,
        "link_name" => link_name,
        "provider_id" => provider_id,
        "values" => values
      })

    case ctl_request(prefix, topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :no_responders} ->
        {:error, "No responders to put link definition"}

      {:error, :timeout} ->
        {:error, "Request to put link definition timed out"}
    end
  end

  def delete_linkdef(actor_id, contract_id, link_name) do
    {_pk, _pid, prefix} = WasmcloudHost.Application.first_host()

    topic = "#{@wasmbus_prefix}#{prefix}.linkdefs.del"

    payload =
      Jason.encode!(%{
        "actor_id" => actor_id,
        "contract_id" => contract_id,
        "link_name" => link_name
      })

    case ctl_request(prefix, topic, payload, 2_000) do
      {:ok, %{body: body}} ->
        resp = Jason.decode!(body)

        if Map.get(resp, "accepted", false) do
          :ok
        else
          {:error, Map.get(resp, "error", "")}
        end

      {:error, :no_responders} ->
        {:error, "No responders to linkdef delete"}

      {:error, :timeout} ->
        {:error, "Request to delete linkdef timed out"}
    end
  end

  defp ctl_request(prefix, topic, payload, timeout) do
    Gnat.request(HostCore.Nats.control_connection(prefix), topic, payload,
      request_timeout: timeout
    )
  end
end
