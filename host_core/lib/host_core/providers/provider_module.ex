defmodule HostCore.Providers.ProviderModule do
  use GenServer, restart: :transient
  require Logger
  alias HostCore.CloudEvent

  @thirty_seconds 30_000

  defmodule State do
    defstruct [
      :os_port,
      :os_pid,
      :link_name,
      :contract_id,
      :public_key,
      :lattice_prefix,
      :instance_id
    ]
  end

  @doc """
  Starts the provider module assuming it is an executable file
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def identity_tuple(pid) do
    GenServer.call(pid, :identity_tuple)
  end

  def instance_id(pid) do
    GenServer.call(pid, :get_instance_id)
  end

  def halt(pid) do
    GenServer.call(pid, :halt_cleanup)
  end

  @impl true
  def init({:executable, path, public_key, link_name, contract_id, oci}) do
    Logger.info("Starting executable capability provider at  '#{path}'")

    # In case we want to know the contract ID of this provider, we can look it up as the
    # bound value in the registry.

    # Store the provider pid
    Registry.register(Registry.ProviderRegistry, {public_key, link_name}, contract_id)
    # Store the provider triple in an ETS table
    HostCore.Providers.register_provider(public_key, link_name, contract_id)

    instance_id = UUID.uuid4()

    host_info =
      HostCore.Host.generate_hostinfo_for(public_key, link_name, instance_id)
      |> Base.encode64()
      |> to_charlist()

    port = Port.open({:spawn, "#{path}"}, [:binary])
    Port.monitor(port)
    Port.command(port, "#{host_info}\n")

    {:os_pid, pid} = Port.info(port, :os_pid)

    # Worth pointing out here that this process doesn't need to subscribe to
    # the provider's NATS topic. The provider now subscribes to that directly
    # when it starts.

    publish_provider_started(public_key, link_name, contract_id, instance_id)

    if oci != nil && oci != "" do
      publish_provider_oci_map(public_key, link_name, oci)
    end

    Process.send_after(self(), :do_health, @thirty_seconds)

    {:ok,
     %State{
       os_port: port,
       os_pid: pid,
       public_key: public_key,
       link_name: link_name,
       contract_id: contract_id,
       instance_id: instance_id,
       lattice_prefix: HostCore.Host.lattice_prefix()
     }}
  end

  @impl true
  def handle_call(:halt_cleanup, _from, state) do
    # Elixir cleans up ports, but it doesn't always clean up the OS process it created
    # for that port. TODO - find a clean, reliable way of killing these processes.
    if state.os_pid != nil do
      System.cmd("kill", ["-9", "#{state.os_pid}"])
    end

    publish_provider_stopped(state.public_key, state.link_name, state.instance_id, "normal")
    {:stop, :normal, :ok, state}
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
  def handle_info({_ref, {:data, logline}}, state) do
    Logger.info("[#{state.public_key}]: #{logline}")

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :port, _port, :normal}, state) do
    Logger.debug("Received DOWN message from port (executable stopped normally)")

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :port, _port, reason}, state) do
    Logger.error("Received DOWN message from port (executable stopped) - #{reason}")
    publish_provider_stopped(state.public_key, state.link_name, state.instance_id, "#{reason}")
    {:stop, reason, state}
  end

  @impl true
  def handle_info(:do_health, state) do
    topic = "wasmbus.rpc.#{state.lattice_prefix}.#{state.public_key}.#{state.link_name}.health"
    payload = %{placeholder: true} |> Msgpax.pack!() |> IO.iodata_to_binary()

    res =
      try do
        Gnat.request(:lattice_nats, topic, payload, receive_timeout: 2_000)
      rescue
        _e -> {:error, "Received no response on health check topic from provider"}
      end

    case res do
      {:ok, _body} -> publish_health_passed(state)
      {:error, _} -> publish_health_failed(state)
    end

    Process.send_after(self(), :do_health, @thirty_seconds)
    {:noreply, state}
  end

  def handle_info({_ref, msg}, state) do
    Logger.info(msg)

    {:noreply, state}
  end

  defp publish_provider_oci_map(public_key, _link_name, oci) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        oci_url: oci,
        public_key: public_key
      }
      |> Msgpax.pack!()
      |> IO.iodata_to_binary()

    topic = "wasmbus.rpc.#{prefix}.refmaps.put"
    Gnat.pub(:lattice_nats, topic, msg)
  end

  defp publish_health_passed(state) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: state.public_key,
        link_name: state.link_name
      }
      |> CloudEvent.new("health_check_passed")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  defp publish_health_failed(state) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: state.public_key,
        link_name: state.link_name
      }
      |> CloudEvent.new("health_check_failed")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  @spec publish_provider_stopped(String.t(), String.t(), String.t(), String.t()) :: :ok
  def publish_provider_stopped(public_key, link_name, instance_id, reason) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: public_key,
        link_name: link_name,
        instance_id: instance_id,
        reason: reason
      }
      |> CloudEvent.new("provider_stopped")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end

  defp publish_provider_started(pk, link_name, contract_id, instance_id) do
    prefix = HostCore.Host.lattice_prefix()

    msg =
      %{
        public_key: pk,
        link_name: link_name,
        contract_id: contract_id,
        instance_id: instance_id
      }
      |> CloudEvent.new("provider_started")

    topic = "wasmbus.evt.#{prefix}"

    Gnat.pub(:control_nats, topic, msg)
  end
end
