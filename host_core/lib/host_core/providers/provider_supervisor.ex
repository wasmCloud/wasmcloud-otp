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
    case Registry.count_match(Registry.ProviderRegistry, {public_key, link_name}, :_) do
      0 ->
        DynamicSupervisor.start_child(
          __MODULE__,
          {ProviderModule, {:executable, path, public_key, link_name, contract_id}}
        )

      _ ->
        {:error, "Provider is already running on this host"}
    end
  end

  def handle_info(msg, state) do
    Logger.error("Supervisor received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def terminate_provider(public_key, link_name) do
    [{pid, _val}] = Registry.lookup(Registry.ProviderRegistry, {public_key, link_name})
    Logger.info("About to terminate child process")
    # TODO: send NATS shutdown message
    prefix = Host.lattice_prefix()
    :ok = Gnat.pub(:lattice_nats, "wasmbus.rpc.#{prefix}.#{public_key}.#{link_name}", "")
    ProviderModule.halt(pid)
  end

  @doc """
  Produces a list of tuples in the form of {public_key, link_name, contract_id}
  of all of the current providers running
  """
  def all_providers() do
    Supervisor.which_children(HostCore.Providers.ProviderSupervisor)
    |> Enum.map(fn {_d, pid, _type, _modules} ->
      provider_for_pid(pid)
    end)
  end

  def provider_for_pid(pid) do
    case List.first(Registry.keys(Registry.ProviderRegistry, pid)) do
      {public_key, link_name} ->
        {public_key, link_name, lookup_contract_id(public_key, link_name)}

      nil ->
        nil
    end
  end

  defp lookup_contract_id(public_key, link_name) do
    Registry.lookup(Registry.ProviderRegistry, {public_key, link_name})
    |> Enum.map(fn {_pid, contract_id} -> contract_id end)
    |> List.first()
  end
end
