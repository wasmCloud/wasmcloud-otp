defmodule HostCore.Providers.ProviderSupervisor do
  use DynamicSupervisor
  require Logger
  alias HostCore.Providers.ProviderModule

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_executable_provider(path, public_key, link_name, contract_id) do
    # TODO - block the attempt to start the same triplet (pk, link, contract) twice

    DynamicSupervisor.start_child(
      __MODULE__,
      {ProviderModule, {:executable, path, public_key, link_name, contract_id}}
    )
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.info("A child process died: #{reason}")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error("Supervisor received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def terminate_provider(public_key, link_name) do
    [{pid, _val}] = Registry.lookup(Registry.ProviderRegistry, {public_key, link_name})
    Logger.info("About to terminate child process")
    ProviderModule.halt(pid)
  end

  def all_providers() do
    children()
    |> get_key()
    |> get_value()
  end

  defp children() do
    Supervisor.which_children(HostCore.Providers.ProviderSupervisor)
  end

  defp get_key(children) do
    children
    |> Enum.flat_map(fn {_id, pid, _type, _modules} ->
      Registry.keys(Registry.ProviderRegistry, pid)
    end)
  end

  defp get_value(provlist) do
    provlist
    |> Enum.map(fn {pk, link_name} ->
      {pk, link_name,
       Registry.lookup(Registry.ProviderRegistry, {pk, link_name}) |> clean_lookup()}
    end)
  end

  defp clean_lookup([{_pid, contract_id}]) do
    contract_id
  end
end
