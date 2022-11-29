defmodule HostCore.Nats do
  @moduledoc """
  The NATS module provides a few special utility functions. The main functions in this module allow consumers to obtain the
  appropriate atom for a given RPC or control connection. Note that while there is a finite limit on atoms in a BEAM, the limit
  is often in the millions and if we have hundreds of thousands of lattices running inside a single OTP application, we have other
  problems to worry about.

  In addition to obtaining the appropriate connection atom, this module also exposes the `safe_pub` and `safe_req` wrappers around
  core Gnat functionality.
  """
  require Logger

  def rpc_connection_settings(opts) do
    %{
      # (required) the registered named you want to give the Gnat connection
      name: rpc_connection(opts.lattice_prefix),
      # number of milliseconds to wait between consecutive reconnect attempts (default: 2_000)
      backoff_period: 4_000,
      connection_settings: [
        Map.merge(
          %{
            host: opts.rpc_host,
            port: opts.rpc_port,
            no_responders: true,
            tls: opts.rpc_tls,
            tcp_opts: determine_ipv6(opts.enable_ipv6)
          },
          determine_auth_method(opts.rpc_seed, opts.rpc_jwt, "lattice rpc")
        )
      ]
    }
  end

  def control_connection_settings(opts) do
    %{
      # (required) the registered named you want to give the Gnat connection
      name: control_connection(opts.lattice_prefix),

      # number of milliseconds to wait between consecutive reconnect attempts (default: 2_000)
      backoff_period: 4_000,
      connection_settings: [
        Map.merge(
          %{
            host: opts.ctl_host,
            port: opts.ctl_port,
            tls: opts.ctl_tls,
            no_responders: true,
            tcp_opts: determine_ipv6(opts.enable_ipv6)
          },
          determine_auth_method(opts.ctl_seed, opts.ctl_jwt, "control interface")
        )
      ]
    }
  end

  def control_connection(lattice_prefix), do: String.to_atom("#{lattice_prefix}-ctl")

  def rpc_connection(lattice_prefix) do
    String.to_atom("#{lattice_prefix}-rpc")
  end

  def sanitize_for_topic(input) do
    Base.url_encode64(input, padding: false)
  end

  defp determine_auth_method(nkey_seed, jwt, conn_name) do
    cond do
      jwt != "" && nkey_seed != "" ->
        Logger.info("Authenticating to #{conn_name} NATS with JWT and seed")
        %{jwt: jwt, nkey_seed: nkey_seed, auth_required: true}

      nkey_seed != "" ->
        Logger.info("Authenticating to #{conn_name} NATS with seed")
        %{nkey_seed: nkey_seed, auth_required: true}

      # No arguments specified that create a valid authentication method
      true ->
        Logger.info("Will connect to #{conn_name} NATS without authentication")
        %{}
    end
  end

  defp determine_ipv6(true), do: [:binary, :inet6]
  defp determine_ipv6(_), do: [:binary]

  def safe_pub(process_name, topic, msg) do
    if Process.whereis(process_name) != nil do
      trace_context = :otel_propagator_text_map.inject([])
      Gnat.pub(process_name, topic, msg, headers: trace_context)
    else
      Logger.error("Publication on #{topic} aborted - connection #{process_name} is down",
        nats_topic: topic
      )
    end
  end

  def safe_req(process_name, topic, body, opts \\ []) do
    if Process.whereis(process_name) != nil do
      trace_context = :otel_propagator_text_map.inject([])
      opts = opts ++ [headers: trace_context]
      Gnat.request(process_name, topic, body, opts)
    else
      Logger.error(
        "NATS request for #{topic} aborted, connection #{process_name} is down. Returning 'fast timeout'",
        nats_topic: topic
      )

      {:error, :timeout}
    end
  end
end
