defmodule HostCore.ConfigPlan do
  @moduledoc """
  `ConfigPlan` provide configuration options.
  """
  @behaviour Vapor.Plan

  alias Vapor.Provider.{Dotenv, Env}

  @prefix_var "WASMCLOUD_LATTICE_PREFIX"
  @hostkey_var "WASMCLOUD_HOST_KEY"
  @hostseed_var "WASMCLOUD_HOST_SEED"
  @default_prefix "default"

  @impl Vapor.Plan
  def config_plan do
    {host_key, host_seed} = HostCore.WasmCloud.Native.generate_key(:server)

    [
      %Dotenv{},
      %Env{
        bindings: [
          # {:cache_deliver_inbox, "_DI", default: "_INBOX.#{hid}"},
          {:host_key, @hostkey_var, default: host_key},
          {:host_seed, @hostseed_var, default: host_seed},
          {:lattice_prefix, @prefix_var, default: @default_prefix},
          {:rpc_host, "WASMCLOUD_RPC_HOST", default: "0.0.0.0"},
          {:rpc_port, "WASMCLOUD_RPC_PORT", default: 4222, map: &String.to_integer/1},
          {:rpc_seed, "WASMCLOUD_RPC_SEED", default: ""},
          {:rpc_timeout, "WASMCLOUD_RPC_TIMEOUT_MS", default: 2000, map: &String.to_integer/1},
          {:rpc_jwt, "WASMCLOUD_RPC_JWT", default: ""},
          {:prov_rpc_host, "WASMCLOUD_PROV_RPC_HOST", default: "0.0.0.0"},
          {:prov_rpc_port, "WASMCLOUD_PROV_RPC_PORT", default: 4222, map: &String.to_integer/1},
          {:prov_rpc_seed, "WASMCLOUD_PROV_RPC_SEED", default: ""},
          {:prov_rpc_jwt, "WASMCLOUD_PROV_RPC_JWT", default: ""},
          {:ctl_host, "WASMCLOUD_CTL_HOST", default: "0.0.0.0"},
          {:ctl_port, "WASMCLOUD_CTL_PORT", default: 4222, map: &String.to_integer/1},
          {:ctl_seed, "WASMCLOUD_CTL_SEED", default: ""},
          {:ctl_jwt, "WASMCLOUD_CTL_JWT", default: ""},
          # {:default_cluster_seed, "_dwcs", default: def_cluster_seed},
          {:cluster_seed, "WASMCLOUD_CLUSTER_SEED", default: ""},
          {:cluster_issuers, "WASMCLOUD_CLUSTER_ISSUERS",
           default: [], map: &String.split(&1, ",")},
          {:provider_delay, "WASMCLOUD_PROV_SHUTDOWN_DELAY_MS",
           default: 300, map: &String.to_integer/1},
          {:allow_latest, "WASMCLOUD_OCI_ALLOW_LATEST", default: false, map: &String.to_atom/1},
          {:allowed_insecure, "WASMCLOUD_OCI_ALLOWED_INSECURE",
           default: [], map: &String.split(&1, ",")}
        ]
      }
    ]
  end
end
