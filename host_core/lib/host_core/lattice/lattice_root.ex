defmodule HostCore.Lattice.LatticeRoot do
  @moduledoc """
  The lattice root will spin up a single lattice supervisor for each lattice that the application
  knows about.
  """

  use DynamicSupervisor

  require Logger

  alias HostCore.Lattice.LatticeSupervisor

  @my_registry Registry.LatticeSupervisorRegistry

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_lattice(config :: HostCore.Vhost.Configuration.t()) :: {:error, any} | {:ok, pid}
  def start_lattice(config) do
    case Registry.lookup(@my_registry, config.lattice_prefix) do
      [] ->
        launch_lattice(config)

      [{pid, _value}] ->
        pid
    end
  end

  @spec launch_lattice(config :: HostCore.Vhost.Configuration.t()) :: {:error, any} | {:ok, pid}
  defp launch_lattice(config) do
    DynamicSupervisor.start_child(__MODULE__, {LatticeSupervisor, config})
  end

  def handle_info(:stop_all, _state) do
    :init.stop()

    {:stop, :shutdown, %{}}
  end

  def via_tuple(lattice_prefix) do
    {:via, Registry, {@my_registry, lattice_prefix, []}}
  end
end
