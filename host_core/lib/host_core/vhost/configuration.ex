defmodule HostCore.Vhost.Configuration do
  @moduledoc """
  The virtual host configuration is a collection of settings that configure a virtual host's ability to communicate
  with NATS and with the rest of a wasmCloud lattice by virtue of cluster signers, user JWTs and seed, etc. Additional
  options and parameters are also available in this stucture.
  """

  alias __MODULE__

  @typedoc """
  The configuration structure for a virtual host
  """
  @type t :: %Configuration{
          prov_rpc_host: String.t(),
          labels: Map.t(),
          rpc_timeout_ms: integer(),
          js_domain: String.t(),
          prov_rpc_seed: String.t(),
          provider_delay: integer(),
          rpc_host: String.t(),
          rpc_jwt: String.t(),
          host_seed: String.t(),
          ctl_tls: boolean(),
          prov_rpc_port: integer(),
          ctl_port: integer(),
          cluster_key: String.t(),
          host_key: String.t(),
          lattice_prefix: String.t(),
          allowed_insecure: [String.t()],
          rpc_tls: boolean(),
          config_service_enabled: boolean(),
          enable_ipv6: boolean(),
          cluster_issuers: [String.t()],
          structured_log_level: atom(),
          prov_rpc_tls: boolean(),
          policy_topic: String.t(),
          ctl_seed: String.t(),
          prov_rpc_jwt: String.t(),
          enable_structured_logging: boolean(),
          allow_latest: boolean(),
          cluster_adhoc: boolean(),
          cache_deliver_inbox: String.t(),
          metadata_deliver_inbox: String.t(),
          policy_changes_topic: String.t(),
          ctl_host: String.t(),
          ctl_jwt: String.t(),
          policy_timeout_ms: integer(),
          rpc_port: integer(),
          ctl_topic_prefix: String.t(),
          rpc_seed: String.t(),
          cluster_seed: String.t()
        }

  @enforce_keys [:lattice_prefix, :cluster_seed, :cluster_issuers, :cluster_key, :host_key]
  defstruct [
    :prov_rpc_host,
    :rpc_timeout_ms,
    :js_domain,
    :prov_rpc_seed,
    :provider_delay,
    :rpc_host,
    :rpc_jwt,
    :host_seed,
    :ctl_tls,
    :ctl_port,
    :prov_rpc_port,
    :cluster_key,
    :host_key,
    :lattice_prefix,
    :allowed_insecure,
    :labels,
    :rpc_tls,
    :config_service_enabled,
    :enable_ipv6,
    :cluster_issuers,
    :structured_log_level,
    :prov_rpc_tls,
    :policy_topic,
    :ctl_seed,
    :prov_rpc_jwt,
    :enable_structured_logging,
    :allow_latest,
    :cluster_adhoc,
    :cache_deliver_inbox,
    :metadata_deliver_inbox,
    :policy_changes_topic,
    :ctl_host,
    :ctl_jwt,
    :policy_timeout_ms,
    :rpc_port,
    :ctl_topic_prefix,
    :rpc_seed,
    :cluster_seed
  ]
end
