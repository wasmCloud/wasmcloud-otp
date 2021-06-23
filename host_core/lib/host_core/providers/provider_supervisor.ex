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

  def start_executable_provider_from_oci(oci, public_key, link_name, contract_id) do
    case HostCore.WasmCloud.Native.get_oci_bytes(oci, false, []) do
      {:error, err} ->
        Logger.error("Failed to download OCI bytes for #{oci}")
        {:stop, err}

      _bytes ->
        dir = System.tmp_dir!()
        filename = String.replace(oci, ":", "_")
        filename = String.replace(filename, "/", "_")
        filename = String.replace(filename, " ", "_")
        filename = String.replace(filename, ".", "_")
        filename = "#{filename}.bin"
        path = Path.join(dir, "wasmcloud_ocicache")
        tmp_file = Path.join(path, filename)
        start_executable_provider(tmp_file, public_key, link_name, contract_id)
    end
  end

  def handle_info(msg, state) do
    Logger.error("Supervisor received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def terminate_provider(public_key, link_name) do
    case Registry.lookup(Registry.ProviderRegistry, {public_key, link_name}) do
      [{pid, _val}] ->
        Logger.info("About to terminate child process")
        prefix = HostCore.Host.lattice_prefix()
        # Allow provider 2 seconds to clean up resources
        case Gnat.request(
               :lattice_nats,
               "wasmbus.rpc.#{prefix}.#{public_key}.#{link_name}.shutdown",
               "",
               receive_timeout: 2000
             ) do
          {:ok, _msg} -> :ok
          {:error, :timeout} -> :error
        end

        ProviderModule.halt(pid)

      [] ->
        Logger.warn("No provider is running with that public key and link name")
    end
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
