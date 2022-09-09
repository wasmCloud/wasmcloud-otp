defmodule HostCore.Providers.ProviderSupervisor do
  @moduledoc false
  use DynamicSupervisor
  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  alias HostCore.Providers.ProviderModule

  @start_provider "start_provider"
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
         oci,
         config_json,
         annotations
       ) do
    with %{permitted: true} <-
           HostCore.Policy.Manager.evaluate_action(
             %{
               publicKey: "",
               contractId: "",
               linkName: "",
               capabilities: [],
               issuer: "",
               issuedOn: "",
               expiresAt: DateTime.utc_now() |> DateTime.add(60) |> DateTime.to_unix(),
               expired: false
             },
             %{
               publicKey: claims.public_key,
               issuer: claims.issuer,
               linkName: link_name,
               contractId: contract_id
             },
             @start_provider
           ),
         0 <- Registry.count_match(Registry.ProviderRegistry, {claims.public_key, link_name}, :_) do
      DynamicSupervisor.start_child(
        __MODULE__,
        {ProviderModule,
         {:executable, path, claims, link_name, contract_id, oci, config_json, annotations}}
      )
    else
      %{permitted: false, message: message, requestId: request_id} ->
        Tracer.set_status(:error, "Policy denied starting provider, request: #{request_id}")
        {:error, "Starting provider #{claims.public_key} denied: #{message}"}

      _ ->
        {:error, "Provider is already running on this host"}
    end
  end

  def start_provider_from_oci(ref, link_name, config_json \\ "", annotations \\ %{}) do
    Tracer.with_span "Start Provider from OCI" do
      creds = HostCore.Host.get_creds(:oci, ref)
      Tracer.set_attribute("oci_ref", ref)
      Tracer.set_attribute("link_name", link_name)

      with {:ok, path} <-
             HostCore.WasmCloud.Native.get_oci_path(
               creds,
               ref,
               HostCore.Oci.allow_latest(),
               HostCore.Oci.allowed_insecure()
             ),
           {:ok, par} <-
             HostCore.WasmCloud.Native.par_from_path(
               path,
               link_name
             ) do
        Tracer.add_event("Provider fetched", [])

        start_executable_provider(
          HostCore.WasmCloud.Native.par_cache_path(
            par.claims.public_key,
            par.claims.revision,
            par.contract_id,
            link_name
          ),
          par.claims,
          link_name,
          par.contract_id,
          ref,
          config_json,
          annotations
        )
      else
        {:error, err} ->
          Logger.error("Error starting provider from OCI: #{err}",
            oci_ref: ref,
            link_name: link_name
          )

          Tracer.set_status(:error, "#{err}")

          {:error, err}

        err ->
          Tracer.set_status(:error, "#{inspect(err)}")
          Logger.error("Error starting provider from OCI: #{inspect(err)}", oci_ref: ref)
          {:error, "Error starting provider from OCI"}
      end
    end
  end

  def start_provider_from_bindle(bindle_id, link_name, config_json \\ "", annotations \\ %{}) do
    Tracer.with_span "Start Provider from Bindle" do
      creds = HostCore.Host.get_creds(:bindle, bindle_id)
      Tracer.set_attribute("bindle_id", bindle_id)
      Tracer.set_attribute("link_name", link_name)

      with {:ok, par} <-
             HostCore.WasmCloud.Native.get_provider_bindle(
               creds,
               String.trim_leading(bindle_id, "bindle://"),
               link_name
             ) do
        Tracer.add_event("Provider fetched", [])

        start_executable_provider(
          HostCore.WasmCloud.Native.par_cache_path(
            par.claims.public_key,
            par.claims.revision,
            par.contract_id,
            link_name
          ),
          par.claims,
          link_name,
          par.contract_id,
          bindle_id,
          config_json,
          annotations
        )
      else
        {:error, err} ->
          Logger.error("Error starting provider from Bindle: #{inspect(err)}",
            bindle_id: bindle_id,
            link_name: link_name
          )

          Tracer.set_status(:error, "#{inspect(err)}")
          {:error, err}

        err ->
          Logger.error("Error starting provider from Bindle: #{inspect(err)}",
            bindle_id: bindle_id,
            link_name: link_name
          )

          Tracer.set_status(:error, "#{inspect(err)}")

          {:error, "Error starting provider from Bindle"}
      end
    end
  end

  def start_provider_from_file(path, link_name, annotations \\ %{}) do
    Tracer.with_span "Start Provider from File" do
      with {:ok, par} <- HostCore.WasmCloud.Native.par_from_path(path, link_name) do
        start_executable_provider(
          HostCore.WasmCloud.Native.par_cache_path(
            par.claims.public_key,
            par.claims.revision,
            par.contract_id,
            link_name
          ),
          par.claims,
          link_name,
          par.contract_id,
          "",
          "",
          annotations
        )
      else
        {:error, err} ->
          Logger.error("Error starting provider from file: #{err}", link_name: link_name)
          {:error, err}

        err ->
          Logger.error("Error starting provider from file: #{err}", link_name: link_name)
          {:error, err}
      end
    end
  end

  def handle_info(msg, state) do
    Logger.warn("Supervisor received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  def provider_running?(reference, link_name) do
    key =
      if String.starts_with?(reference, "V") do
        reference
      else
        case HostCore.Refmaps.Manager.lookup_refmap(reference) do
          {:ok, {_oci, pk}} -> pk
          _ -> ""
        end
      end

    if String.length(key) > 0 do
      case Registry.lookup(Registry.ProviderRegistry, {key, link_name}) do
        [{_pid, _val}] ->
          true

        _ ->
          false
      end
    else
      false
    end
  end

  def terminate_provider(public_key, link_name) do
    Tracer.with_span "Terminate Provider", kind: :server do
      case Registry.lookup(Registry.ProviderRegistry, {public_key, link_name}) do
        [{pid, _val}] ->
          Logger.info("About to terminate child process",
            provider_id: public_key,
            link_name: link_name
          )

          Tracer.set_attribute("public_key", public_key)
          Tracer.set_attribute("link_name", link_name)

          prefix = HostCore.Host.lattice_prefix()

          # Allow provider 2 seconds to respond/acknowledge termination request (give time to clean up resources)
          case HostCore.Nats.safe_req(
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
          Logger.warn(
            "No provider is running with public key #{public_key} and link name \"#{link_name}\"",
            provider_id: public_key,
            link_name: link_name
          )
      end
    end
  end

  def terminate_all() do
    all_providers()
    |> Enum.each(fn {_pid, pk, link, _contract, _instance_id} -> terminate_provider(pk, link) end)
  end

  @doc """
  Produces a list of tuples in the form of {pid, public_key, link_name, contract_id, instance_id}
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
