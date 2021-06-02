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

      DynamicSupervisor.start_child(__MODULE__, {ProviderModule, {:executable, path, public_key, link_name, contract_id}})
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

      provs = providers_by_pid()
      |> Enum.filter(fn { {pk, ln}, _pid} -> pk == public_key && ln == link_name end)
      |> Enum.take(1)

      if length(provs) == 1 do
        [{{pk, ln}, pid}] = provs
        ProviderModule.cleanup(pid) # removes underlying OS process if one exists
        ProviderModule.publish_provider_stopped(pk, ln)
        Process.exit(pid, :manual_shutdown)
      end

    end

    defp providers_by_pid() do
      Supervisor.which_children(__MODULE__)
      |> Enum.map(fn {_id, pid, _type_, _modules} ->
        { ProviderModule.identity_tuple(pid), pid} end)
    end

end
