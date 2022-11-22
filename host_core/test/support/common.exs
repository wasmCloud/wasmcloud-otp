defmodule HostCoreTest.Common do
  require Logger

  def request_http(url, retries) when retries > 0 do
    case HTTPoison.get(url) do
      {:ok, resp} ->
        {:ok, resp}

      _ ->
        Logger.debug("HTTP request failed, retrying in 1000ms, remaining retries #{retries}")
        :timer.sleep(1000)
        request_http(url, retries - 1)
    end
  end

  def request_http(_url, 0) do
    # IO.puts("YO! YOUR HTTP LIBRARY MAY BE MESSED UP, CURL #{url}")
    # :timer.sleep(60000)
    {:error, "Connection refused after retries"}
  end

  def sudo_make_me_a_host(lattice_id) when is_binary(lattice_id) do
    config = default_vhost_config()
    config = %{config | lattice_prefix: lattice_id}

    HostCore.Vhost.VirtualHost.start_link(config)
  end

  def standard_setup(_context) do
    lattice_id = UUID.uuid4()
    {:ok, host_pid} = HostCoreTest.Common.sudo_make_me_a_host(lattice_id)

    {:ok, evt_watcher} = GenServer.start_link(HostCoreTest.EventWatcher, lattice_id)

    [
      evt_watcher: evt_watcher,
      host_pid: host_pid,
      hconfig: HostCore.Vhost.VirtualHost.config(host_pid)
    ]
  end

  def cleanup(pid, config) do
    HostCore.Vhost.VirtualHost.stop(pid, 300)
    purge_topic = "$JS.API.STREAM.DELETE.LATTICECACHE_#{config.lattice_prefix}"

    case HostCore.Nats.safe_req(
           HostCore.Nats.control_connection(config.lattice_prefix),
           purge_topic,
           []
         ) do
      {:ok, %{body: _body}} ->
        Logger.debug("Purged NATS stream for lattice cache")

      {:error, :timeout} ->
        Logger.error("Failed to purge NATS stream for lattice cache within timeout")
    end
  end

  def default_vhost_config() do
    {pk, seed} = HostCore.WasmCloud.Native.generate_key(:server)
    {ck, cseed} = HostCore.WasmCloud.Native.generate_key(:cluster)

    s =
      Hashids.new(
        salt: "lc_deliver_inbox",
        min_len: 2
      )

    hid = Hashids.encode(s, Enum.random(1..4_294_967_295))

    %{
      lattice_prefix: "default",
      cache_deliver_inbox: "_INBOX.#{hid}",
      host_seed: seed,
      cluster_key: ck,
      cluster_adhoc: false,
      host_key: pk,
      rpc_host: "127.0.0.1",
      rpc_port: 4222,
      rpc_seed: "",
      rpc_timeout_ms: 2000,
      rpc_jwt: "",
      rpc_tls: false,
      prov_rpc_host: "127.0.0.1",
      prov_rpc_port: 4222,
      prov_rpc_seed: "",
      prov_rpc_tls: false,
      prov_rpc_jwt: "",
      ctl_host: "127.0.0.1",
      ctl_seed: "",
      ctl_jwt: "",
      ctl_port: 4222,
      ctl_tls: false,
      ctl_topic_prefix: "wasmbus.ctl",
      cluster_seed: cseed,
      cluster_issuers: [ck],
      provider_delay: 300,
      allow_latest: false,
      allowed_insecure: [],
      js_domain: nil,
      config_service_enabled: false,
      enable_structured_logging: false,
      structure_log_level: :info,
      enable_ipv6: false,
      policy_topic: nil,
      policy_changes_topic: nil,
      policy_timeout: 1_000
    }
  end
end
