defmodule HostCore.ConfigPlan do
  @moduledoc """
  `ConfigPlan` provide configuration options.
  """
  @behaviour Vapor.Plan

  alias Vapor.Provider.{Dotenv, Env}
  alias HostCore.FilesConfigProvider

  @prefix_var "WASMCLOUD_LATTICE_PREFIX"
  @default_prefix "default"

  @impl Vapor.Plan
  def config_plan do
    [
      %Dotenv{},
      %FilesConfigProvider{
        paths: ["host_config.json"],
        bindings: json_bindings()
      },
      # Default values will be in the merged accumulator at this point,
      # so we don't specify them here
      %Env{
        bindings: [
          {:lattice_prefix, @prefix_var, required: false},
          {:host_seed, "WASMCLOUD_HOST_SEED", required: false},
          {:rpc_host, "WASMCLOUD_RPC_HOST", required: false},
          {:rpc_port, "WASMCLOUD_RPC_PORT", required: false, map: &String.to_integer/1},
          {:rpc_seed, "WASMCLOUD_RPC_SEED", required: false},
          {:rpc_timeout, "WASMCLOUD_RPC_TIMEOUT_MS", required: false, map: &String.to_integer/1},
          {:rpc_jwt, "WASMCLOUD_RPC_JWT", required: false},
          {:rpc_tls, "WASMCLOUD_RPC_TLS", required: false, map: &String.to_integer/1},
          {:prov_rpc_host, "WASMCLOUD_PROV_RPC_HOST", required: false},
          {:prov_rpc_port, "WASMCLOUD_PROV_RPC_PORT", required: false, map: &String.to_integer/1},
          {:prov_rpc_seed, "WASMCLOUD_PROV_RPC_SEED", required: false},
          {:prov_rpc_tls, "WASMCLOUD_PROV_RPC_TLS", required: false, map: &String.to_integer/1},
          {:prov_rpc_jwt, "WASMCLOUD_PROV_RPC_JWT", required: false},
          {:ctl_host, "WASMCLOUD_CTL_HOST", required: false},
          {:ctl_port, "WASMCLOUD_CTL_PORT", required: false, map: &String.to_integer/1},
          {:ctl_seed, "WASMCLOUD_CTL_SEED", required: false},
          {:ctl_seed, "WASMCLOUD_CTL_SEED", required: false},
          {:ctl_jwt, "WASMCLOUD_CTL_JWT", required: false},
          {:ctl_tls, "WASMCLOUD_CTL_TLS", required: false, map: &String.to_integer/1},
          {:cluster_seed, "WASMCLOUD_CLUSTER_SEED", required: false},
          {:cluster_issuers, "WASMCLOUD_CLUSTER_ISSUERS",
           required: false, map: &String.split(&1, ",")},
          {:provider_delay, "WASMCLOUD_PROV_SHUTDOWN_DELAY_MS",
           required: false, map: &String.to_integer/1},
          {:allow_latest, "WASMCLOUD_OCI_ALLOW_LATEST", required: false, map: &String.to_atom/1},
          {:allowed_insecure, "WASMCLOUD_OCI_ALLOWED_INSECURE",
           required: false, map: &String.split(&1, ",")},
          {:js_domain, "WASMCLOUD_JS_DOMAIN", required: false}
        ]
      }
    ]
  end

  defp json_bindings() do
    [
      {:lattice_prefix, "lattice_prefix", required: false, default: @default_prefix},
      {:host_seed, "host_seed", required: false, default: nil},
      {:rpc_host, "rpc_host", required: false, default: "127.0.0.1"},
      {:rpc_port, "rpc_port", required: false, default: 4222},
      {:rpc_seed, "rpc_seed", required: false, default: ""},
      {:rpc_timeout, "rpc_timeout_ms", required: false, default: 2000},
      {:rpc_jwt, "rpc_jwt", required: false, default: ""},
      {:rpc_tls, "rpc_tls", required: false, default: 0},
      {:prov_rpc_host, "prov_rpc_host", required: false, default: "127.0.0.1"},
      {:prov_rpc_port, "prov_rpc_port", required: false, default: 4222},
      {:prov_rpc_seed, "prov_rpc_seed", required: false, default: ""},
      {:prov_rpc_tls, "prov_rpc_tls", required: false, default: 0},
      {:prov_rpc_jwt, "prov_rpc_jwt", required: false, default: ""},
      {:ctl_host, "ctl_host", required: false, default: "127.0.0.1"},
      {:ctl_port, "ctl_port", required: false, default: 4222},
      {:ctl_seed, "ctl_seed", required: false, default: ""},
      {:ctl_jwt, "ctl_jwt", required: false, default: ""},
      {:ctl_tls, "ctl_tls", required: false, default: 0},
      {:cluster_seed, "cluster_seed", required: false, default: ""},
      {:cluster_issuers, "cluster_issuers", required: false, default: []},
      {:provider_delay, "provider_delay", required: false, default: 300},
      {:allow_latest, "allow_latest", required: false, default: false},
      {:allowed_insecure, "allowed_insecure", required: false, default: []},
      {:js_domain, "js_domain", required: false, default: nil}
    ]
  end
end
