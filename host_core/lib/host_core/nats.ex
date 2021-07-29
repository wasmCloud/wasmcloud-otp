defmodule HostCore.Nats do
  require Logger

  def rpc_connection_settings(opts) do
    %{
      # (required) the registered named you want to give the Gnat connection
      name: :lattice_nats,
      # number of milliseconds to wait between consecutive reconnect attempts (default: 2_000)
      backoff_period: 4_000,
      connection_settings: [
        Map.merge(
          %{host: opts.rpc_host, port: opts.rpc_port},
          determine_auth_method(opts.rpc_seed, opts.rpc_jwt, "lattice rpc")
        )
      ]
    }
  end

  def control_connection_settings(opts) do
    %{
      # (required) the registered named you want to give the Gnat connection
      name: :control_nats,
      # number of milliseconds to wait between consecutive reconnect attempts (default: 2_000)
      backoff_period: 4_000,
      connection_settings: [
        Map.merge(
          %{host: opts.ctl_host, port: opts.ctl_port},
          determine_auth_method(opts.ctl_seed, opts.ctl_jwt, "control interface")
        )
      ]
    }
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
        Logger.info("Connecting to #{conn_name} NATS without authentication")
        %{}
    end
  end
end
