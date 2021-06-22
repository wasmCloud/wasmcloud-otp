defmodule HostCore.NatsSupervisor do
  require Logger
  use GenServer, restart: :transient

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    config = List.first(init_arg)
    Logger.info("Connecting to NATS")
    {:ok, config, {:continue, :connect_rpc}}
  end

  @impl true
  def handle_continue(:connect_rpc, config) do
    Logger.info("Starting RPC connection")

    case lattice_connect(config.rpc_host, config.rpc_port) do
      {:ok, _gnat} ->
        {:noreply, config, {:continue, :connect_control}}

      {:error, _} ->
        Logger.warn(
          "Failed to connect to lattice at #{config.rpc_host}:#{config.rpc_port}, retrying in 1 second..."
        )

        {:noreply, config, {:continue, :connect_rpc}}
    end
  end

  @impl true
  def handle_continue(:connect_control, config) do
    Logger.info("Starting the control interface connection")

    {:noreply, config, {:continue, :start_children}}
  end

  @impl true
  def handle_continue(:start_children, _config) do
    Logger.info("Startin' the kids")
    start_children()

    {:stop, :normal, %{}}
  end

  # @impl true
  # def handle_info(
  #       :connect_lattice,
  #       config
  #     ) do
  #   Logger.info("Connecting to Lattice")

  #   case lattice_connect(config.rpc_host, config.rpc_port) do
  #     {:ok, _gnat} ->
  #       check_children()

  #     {:error, _} ->
  #       Logger.warn(
  #         "Failed to connect to lattice at #{config.rpc_host}:#{config.rpc_port}, retrying in 1 second..."
  #       )

  #       Process.send_after(
  #         self(),
  #         :connect_lattice,
  #         1_000
  #       )
  #   end

  #   {:noreply, config}
  # end

  # def handle_info(:connect_control, config) do
  #   case control_connect(config.ctl_host, config.ctl_port) do
  #     {:ok, _gnat} ->
  #       check_children()

  #     {:error, _} ->
  #       Logger.warn(
  #         "Failed to connect to control interface at #{config.ctl_host}:#{config.ctl_port}, retrying in 1 second..."
  #       )

  #       Process.send_after(
  #         self(),
  #         :connect_control,
  #         1_000
  #       )
  #   end

  #   {:noreply, config}
  # end

  defp start_children() do
    children = [
      {HostCore.Providers.ProviderSupervisor, strategy: :one_for_one, name: ProviderRoot},
      {HostCore.Actors.ActorSupervisor, strategy: :one_for_one, name: ActorRoot},
      {HostCore.LinkdefsManager, strategy: :one_for_one, name: LinkdefsManager},
      {HostCore.ClaimsManager, strategy: :one_for_one, name: ClaimsManager}
    ]

    Process.sleep(1_000)

    for child <- children, do: Supervisor.start_child(HostCore.Application, child)
  end

  defp lattice_connect(rpc_host, rpc_port) do
    Gnat.start_link(%{host: rpc_host, port: rpc_port}, name: :lattice_nats)
  end

  defp control_connect(ctl_host, ctl_port) do
    Gnat.start_link(%{host: ctl_host, port: ctl_port}, name: :control_nats)
  end
end
