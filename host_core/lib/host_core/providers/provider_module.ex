defmodule HostCore.Providers.ProviderModule do
  @moduledoc """
  The provider module is an OTP process designed to manage a single instance of a capability provider within a single virtual
  host. At the moment, capability providers are native OS binaries and, as such, this process is designed to spawn a running
  child process of that binary and manage the interaction with it. Unlike actors, capability providers are responsible for subscribing
  to their RPC topics on their own.
  """

  use GenServer, restart: :transient
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias HostCore.CloudEvent

  @thirty_seconds 30_000

  defmodule State do
    @moduledoc false

    defstruct [
      :os_port,
      :os_pid,
      :shutdown_delay,
      :link_name,
      :contract_id,
      :public_key,
      :lattice_prefix,
      :instance_id,
      :host_id,
      :annotations,
      :executable_path,
      :ociref,
      :healthy
    ]
  end

  @doc """
  Starts the provider module assuming it is an executable file
  """
  @spec start_link(
          opts ::
            {:executable,
             %{
               host_id: String.t(),
               lattice_prefix: String.t(),
               path: String.t(),
               link_name: String.t(),
               contract_id: String.t(),
               shutdown_delay: non_neg_integer(),
               oci: String.t(),
               config_json: map(),
               annotations: map()
             }}
        ) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def identity_tuple(pid) do
    GenServer.call(pid, :identity_tuple)
  end

  def instance_id(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_instance_id)
    else
      "n/a"
    end
  end

  def contract_id(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_contract_id)
    else
      ""
    end
  end

  def link_name(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_link_name)
    else
      "??"
    end
  end

  def annotations(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_annotations)
    else
      %{}
    end
  end

  def ociref(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_ociref)
    else
      "n/a"
    end
  end

  def public_key(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_public_key)
    else
      "??"
    end
  end

  def path(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_path)
    else
      "n/a"
    end
  end

  def halt(pid) do
    if Process.alive?(pid), do: GenServer.call(pid, :halt_cleanup)
    :ok
  end

  @impl true
  def init(
        {:executable,
         %{
           host_id: host_id,
           lattice_prefix: lattice_prefix,
           path: path,
           claims: claims,
           link_name: link_name,
           contract_id: contract_id,
           shutdown_delay: shutdown_delay,
           oci: oci,
           config_json: config_json,
           annotations: annotations
         }}
      ) do
    Logger.metadata(
      host_id: host_id,
      lattice_prefix: lattice_prefix,
      provider_id: claims.public_key,
      link_name: link_name,
      contract_id: contract_id
    )

    Logger.info("Starting executable capability provider from '#{path}'",
      provider_id: claims.public_key,
      link_name: link_name,
      contract_id: contract_id
    )

    instance_id = UUID.uuid4()

    # Store the provider pid
    Registry.register(Registry.ProviderRegistry, {claims.public_key, link_name}, host_id)

    host_info =
      HostCore.Vhost.VirtualHost.generate_hostinfo_for_provider(
        host_id,
        claims.public_key,
        link_name,
        instance_id,
        config_json
      )
      |> Base.encode64()
      |> to_charlist()

    port = Port.open({:spawn, "#{path}"}, [:binary, {:env, extract_env_vars()}])
    Port.monitor(port)
    Port.command(port, "#{host_info}\n")

    {:os_pid, pid} = Port.info(port, :os_pid)

    # Worth pointing out here that this process doesn't need to subscribe to
    # the provider's NATS topic. The provider subscribes to that directly
    # when it starts.

    HostCore.Claims.Manager.put_claims(host_id, lattice_prefix, claims)

    publish_provider_started(
      host_id,
      lattice_prefix,
      claims,
      link_name,
      contract_id,
      instance_id,
      oci,
      annotations
    )

    if oci != nil && oci != "" do
      publish_provider_oci_map(host_id, lattice_prefix, claims.public_key, link_name, oci)
    end

    Process.send_after(self(), :do_health, 5_000)
    :timer.send_interval(@thirty_seconds, self(), :do_health)

    {:ok,
     %State{
       os_port: port,
       os_pid: pid,
       public_key: claims.public_key,
       link_name: link_name,
       contract_id: contract_id,
       instance_id: instance_id,
       shutdown_delay: shutdown_delay,
       lattice_prefix: lattice_prefix,
       executable_path: path,
       annotations: annotations,
       host_id: host_id,
       # until we prove otherwise
       healthy: false,
       ociref: oci
     }}
  end

  @propagated_env_vars ["OTEL_TRACES_EXPORTER", "OTEL_EXPORTER_OTLP_ENDPOINT"]

  defp extract_env_vars() do
    @propagated_env_vars
    |> Enum.map(fn e -> {e |> to_charlist(), System.get_env(e) |> to_charlist()} end)
    |> Enum.filter(fn {_k, v} -> length(v) > 0 end)
    |> Enum.into([])
  end

  @impl true
  def handle_call(:halt_cleanup, _from, state) do
    Logger.debug("Provider termination requested manually")

    Tracer.with_span "Terminate provider instance", kind: :server do
      case HostCore.Nats.safe_req(
             HostCore.Nats.rpc_connection(state.lattice_prefix),
             "wasmbus.rpc.#{state.lattice_prefix}.#{state.public_key}.#{state.link_name}.shutdown",
             Jason.encode!(%{host_id: state.host_id}),
             receive_timeout: 2000
           ) do
        {:ok, _msg} ->
          Logger.debug("Provider acknowledged shutdown request")

        {:error, :no_responders} ->
          Logger.error("No responders to RPC request to terminate provider")

        {:error, :timeout} ->
          Logger.error("No capability providers responded to RPC shutdown request")
      end

      # Elixir cleans up ports, but it doesn't always clean up the OS process it created
      # for that port. TODO - find a clean, reliable way of killing these processes.
      if state.os_pid != nil do
        # fun fact - if we don't do this in a spawned task, we never move execution
        # to after the if statement. HUZZAH
        Task.Supervisor.start_child(ControlInterfaceTaskSupervisor, fn ->
          System.cmd("kill", ["-9", "#{state.os_pid}"])
        end)
      end

      publish_provider_stopped(
        state.host_id,
        state.lattice_prefix,
        state.public_key,
        state.link_name,
        state.instance_id,
        state.contract_id,
        "normal"
      )

      {:stop, :shutdown, :ok, state}
    end
  end

  @impl true
  def handle_call(:identity_tuple, _from, state) do
    {:reply, {state.public_key, state.link_name}, state}
  end

  @impl true
  def handle_call(:get_instance_id, _from, state) do
    {:reply, state.instance_id, state}
  end

  @impl true
  def handle_call(:get_contract_id, _from, state) do
    {:reply, state.contract_id, state}
  end

  @impl true
  def handle_call(:get_annotations, _from, state) do
    {:reply, state.annotations, state}
  end

  @impl true
  def handle_call(:get_link_name, _from, state) do
    {:reply, state.link_name, state}
  end

  @impl true
  def handle_call(:get_public_key, _from, state) do
    {:reply, state.public_key, state}
  end

  @impl true
  def handle_call(:get_path, _from, state) do
    {:reply, state.executable_path, state}
  end

  @impl true
  def handle_call(:get_ociref, _from, state) do
    {:reply, state.ociref, state}
  end

  @impl true
  def handle_info({_ref, {:data, logline}}, state) do
    Logger.info("[#{state.public_key}]: #{logline}",
      provider_id: state.public_key,
      link_name: state.link_name,
      contract_id: state.contract_id
    )

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :port, _port, :normal}, state) do
    Logger.debug("Received DOWN message from port (provider stopped normally)",
      provider_id: state.public_key,
      link_name: state.link_name,
      contract_id: state.contract_id
    )

    publish_provider_stopped(
      state.host_id,
      state.lattice_prefix,
      state.public_key,
      state.link_name,
      state.instance_id,
      state.contract_id,
      "normal"
    )

    {:stop, :shutdown, state}
  end

  def handle_info({:DOWN, _ref, :port, _port, reason}, state) do
    Logger.error("Received DOWN message from port (provider stopped) - #{reason}",
      provider_id: state.public_key,
      link_name: state.link_name,
      contract_id: state.contract_id
    )

    publish_provider_stopped(
      state.host_id,
      state.lattice_prefix,
      state.public_key,
      state.link_name,
      state.instance_id,
      state.contract_id,
      "#{reason}"
    )

    {:stop, reason, state}
  end

  @impl true
  def handle_info(:do_health, state) do
    topic = "wasmbus.rpc.#{state.lattice_prefix}.#{state.public_key}.#{state.link_name}.health"
    payload = %{placeholder: true} |> Msgpax.pack!() |> IO.iodata_to_binary()
    config = HostCore.Vhost.VirtualHost.config(state.host_id)

    res =
      try do
        HostCore.Nats.safe_req(HostCore.Nats.rpc_connection(state.lattice_prefix), topic, payload,
          receive_timeout: config.rpc_timeout_ms
        )
      rescue
        _e ->
          {:error, "Received no response on health check topic from provider"}
      end

    # Only publish health check pass/fail when state changes
    state =
      case res do
        {:ok, _body} when not state.healthy ->
          publish_health_passed(state)
          %State{state | healthy: true}

        {:ok, _body} ->
          state

        {:error, _} ->
          if state.healthy do
            publish_health_failed(state)
            %State{state | healthy: false}
          else
            state
          end
      end

    {:noreply, state}
  end

  def handle_info({_ref, msg}, state) do
    Logger.debug(msg)

    {:noreply, state}
  end

  defp publish_provider_oci_map(host_id, lattice_prefix, public_key, _link_name, oci) do
    HostCore.Refmaps.Manager.put_refmap(host_id, lattice_prefix, oci, public_key)
  end

  defp publish_health_passed(state) do
    %{
      public_key: state.public_key,
      link_name: state.link_name
    }
    |> CloudEvent.new("health_check_passed", state.host_id)
    |> CloudEvent.publish(state.lattice_prefix)
  end

  defp publish_health_failed(state) do
    %{
      public_key: state.public_key,
      link_name: state.link_name
    }
    |> CloudEvent.new("health_check_failed", state.host_id)
    |> CloudEvent.publish(state.lattice_prefix)
  end

  def publish_provider_stopped(
        host_id,
        lattice_prefix,
        public_key,
        link_name,
        instance_id,
        contract_id,
        reason
      ) do
    %{
      public_key: public_key,
      link_name: link_name,
      contract_id: contract_id,
      instance_id: instance_id,
      reason: reason
    }
    |> CloudEvent.new("provider_stopped", host_id)
    |> CloudEvent.publish(lattice_prefix)
  end

  defp publish_provider_started(
         host_id,
         lattice_prefix,
         claims,
         link_name,
         contract_id,
         instance_id,
         image_ref,
         annotations
       ) do
    %{
      public_key: claims.public_key,
      image_ref: image_ref,
      link_name: link_name,
      contract_id: contract_id,
      instance_id: instance_id,
      annotations: annotations,
      claims: %{
        issuer: claims.issuer,
        tags: claims.tags,
        name: claims.name,
        version: claims.version,
        not_before_human: claims.not_before_human,
        expires_human: claims.expires_human
      }
    }
    |> CloudEvent.new("provider_started", host_id)
    |> CloudEvent.publish(lattice_prefix)
  end
end
