defmodule HostCore.Providers.ProviderSupervisor do
  @moduledoc false
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

  defp start_executable_provider(
         path,
         claims,
         link_name,
         contract_id,
         oci \\ "",
         config_json \\ ""
       ) do
    case Registry.count_match(Registry.ProviderRegistry, {claims.public_key, link_name}, :_) do
      0 ->
        DynamicSupervisor.start_child(
          __MODULE__,
          {ProviderModule, {:executable, path, claims, link_name, contract_id, oci, config_json}}
        )

      _ ->
        {:error, "Provider is already running on this host"}
    end
  end

  defp extract_executable_to_tmp(par, link_name) do
    cache_path =
      HostCore.WasmCloud.Native.par_cache_path(
        par.claims.public_key,
        par.claims.revision,
        par.contract_id,
        link_name
      )

    # Write provider executable to cache if it does not yet exist
    if !File.exists?(cache_path) do
      p = Path.split(cache_path)
      tmpdir = p |> Enum.slice(0, length(p) - 1) |> Path.join()

      with :ok <- File.mkdir_p(tmpdir),
           :ok <- File.write(cache_path, par.target_bytes |> IO.iodata_to_binary()),
           :ok <- File.chmod(cache_path, 0o755) do
        {:ok, cache_path}
      else
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, cache_path}
    end
  end

  def start_provider_from_oci(oci, link_name, config_json \\ "") do
    with {:ok, bytes} <-
           HostCore.WasmCloud.Native.get_oci_bytes(
             oci,
             HostCore.Oci.allow_latest(),
             HostCore.Oci.allowed_insecure()
           ),
         {:ok, par} <- HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary()),
         {:ok, path} <- extract_executable_to_tmp(par, link_name) do
      start_executable_provider(path, par.claims, link_name, par.contract_id, oci, config_json)
    else
      {:error, err} -> Logger.error("Error starting provider from OCI: #{err}")
      _err -> Logger.error("Error starting provider from OCI")
    end
  end

  def start_provider_from_file(path, link_name) do
    with {:ok, bytes} <- File.read(path),
         {:ok, par} <- HostCore.WasmCloud.Native.par_from_bytes(bytes |> IO.iodata_to_binary()),
         {:ok, tmp_path} <- extract_executable_to_tmp(par, link_name) do
      start_executable_provider(
        tmp_path,
        par.claims,
        link_name,
        par.contract_id
      )
    else
      {:error, err} ->
        Logger.error("Error starting provider from file: #{err}")
        {:error, err}

      err ->
        Logger.error("Error starting provider from file")
        err
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

        # Allow provider 2 seconds to respond/acknowledge termination request (give time to clean up resources)
        case Gnat.request(
               :lattice_nats,
               "wasmbus.rpc.#{prefix}.#{public_key}.#{link_name}.shutdown",
               "",
               receive_timeout: 2000
             ) do
          {:ok, _msg} -> :ok
          {:error, :timeout} -> :error
        end

        # Pause for n milliseconds between shutdown request and forceful termination
        Process.sleep(HostCore.Host.provider_shutdown_delay())
        ProviderModule.halt(pid)

      [] ->
        Logger.warn("No provider is running with that public key and link name")
    end
  end

  def terminate_all() do
    all_providers()
    |> Enum.each(fn {_pid, pk, link, _contract, _instance_id} -> terminate_provider(pk, link) end)
  end

  @doc """
  Produces a list of tuples in the form of {public_key, link_name, contract_id, instance_id}
  of all of the current providers running
  """
  def all_providers() do
    Supervisor.which_children(HostCore.Providers.ProviderSupervisor)
    |> Enum.map(fn {_d, pid, _type, _modules} ->
      provider_for_pid(pid)
    end)
    |> Enum.reject(&is_nil/1)
  end

  def provider_for_pid(pid) do
    case List.first(Registry.keys(Registry.ProviderRegistry, pid)) do
      {public_key, link_name} ->
        {pid, public_key, link_name, lookup_contract_id(public_key, link_name),
         HostCore.Providers.ProviderModule.instance_id(pid)}

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
