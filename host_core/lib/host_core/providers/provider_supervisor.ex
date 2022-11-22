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

  def start_provider_from_oci(host_id, ref, link_name, config_json \\ "", annotations \\ %{}) do
    Tracer.with_span "Start Provider from OCI" do
      creds = HostCore.Vhost.VirtualHost.get_creds(host_id, :oci, ref)
      config = HostCore.Vhost.VirtualHost.config(host_id)

      Tracer.set_attribute("oci_ref", ref)
      Tracer.set_attribute("link_name", link_name)
      Tracer.set_attribute("host_id", host_id)

      with {:ok, path} <-
             HostCore.WasmCloud.Native.get_oci_path(
               creds,
               ref,
               config.allow_latest,
               config.allowed_insecure
             ),
           {:ok, par} <-
             HostCore.WasmCloud.Native.par_from_path(
               path,
               link_name
             ) do
        Tracer.add_event("Provider fetched", [])

        start_executable_provider(
          host_id,
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

  def start_provider_from_bindle(
        host_id,
        bindle_id,
        link_name,
        config_json \\ "",
        annotations \\ %{}
      ) do
    Tracer.with_span "Start Provider from Bindle" do
      creds = HostCore.Vhost.VirtualHost.get_creds(host_id, :bindle, bindle_id)

      Tracer.set_attribute("bindle_id", bindle_id)
      Tracer.set_attribute("link_name", link_name)
      Tracer.set_attribute("host_id", host_id)

      with {:ok, par} <-
             HostCore.WasmCloud.Native.get_provider_bindle(
               creds,
               String.trim_leading(bindle_id, "bindle://"),
               link_name
             ) do
        Tracer.add_event("Provider fetched", [])

        start_executable_provider(
          host_id,
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

  def start_provider_from_file(host_id, path, link_name, annotations \\ %{}) do
    Tracer.with_span "Start Provider from File" do
      with {:ok, par} <- HostCore.WasmCloud.Native.par_from_path(path, link_name) do
        start_executable_provider(
          host_id,
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

  def provider_running?(host_id, reference, link_name, public_key) do
    lattice_prefix =
      case HostCore.Vhost.VirtualHost.lookup(host_id) do
        {:ok, {_pid, prefix}} -> prefix
        _ -> "default"
      end

    ref =
      if String.length(reference) > 0 do
        reference
      else
        public_key
      end

    ref
    |> get_reference_key(lattice_prefix)
    |> is_running?(link_name, host_id)
  end

  defp start_executable_provider(
         host_id,
         path,
         claims,
         link_name,
         contract_id,
         oci,
         config_json,
         annotations
       ) do
    config = HostCore.Vhost.VirtualHost.config(host_id)

    source = %{
      publicKey: "",
      contractId: "",
      linkName: "",
      capabilities: [],
      issuer: "",
      issuedOn: "",
      expiresAt: DateTime.utc_now() |> DateTime.add(60) |> DateTime.to_unix(),
      expired: false
    }

    target = %{
      publicKey: claims.public_key,
      issuer: claims.issuer,
      linkName: link_name,
      contractId: contract_id
    }

    with %{permitted: true} <-
           HostCore.Policy.Manager.evaluate_action(
             config,
             source,
             target,
             @start_provider
           ),
         false <- provider_running?(host_id, oci, link_name, claims.public_key) do
      opts = %{
        path: path,
        claims: claims,
        link_name: link_name,
        lattice_prefix: config.lattice_prefix,
        contract_id: contract_id,
        oci: oci,
        config_json: config_json,
        host_id: host_id,
        shutdown_delay: config.provider_delay,
        annotations: annotations
      }

      DynamicSupervisor.start_child(
        __MODULE__,
        {ProviderModule, {:executable, opts}}
      )
    else
      %{permitted: false, message: message, requestId: request_id} ->
        Tracer.set_status(:error, "Policy denied starting provider, request: #{request_id}")
        {:error, "Starting provider #{claims.public_key} denied: #{message}"}

      _ ->
        {:error, "Provider is already running on this host"}
    end
  end

  defp get_reference_key("V" <> _stuff = ref, _lattice_prefix), do: ref

  defp get_reference_key(reference, lattice_prefix) do
    lookup_reference_key(reference, lattice_prefix)
  end

  defp lookup_reference_key(reference, lattice_prefix) do
    case HostCore.Refmaps.Manager.lookup_refmap(lattice_prefix, reference) do
      {:ok, {_oci, pk}} -> pk
      _ -> ""
    end
  end

  defp is_running?(key, _, _) when byte_size(key) == 0, do: false

  defp is_running?(key, link_name, host_id) do
    Enum.any?(
      all_providers(host_id),
      fn {_pid, public_key, ln, _contract_id, _instance_id} ->
        public_key == key && link_name == ln
      end
    )
  end

  def terminate_provider(host_id, public_key, link_name) do
    for {pid, pk, link, _contract_id, _instance_id} <- all_providers(host_id),
        pk == public_key,
        link == link_name do
      Logger.info("About to terminate provider process",
        provider_id: public_key,
        link_name: link_name
      )

      ProviderModule.halt(pid)
    end
  end

  def terminate_all(host_id) when is_binary(host_id) do
    for {pid, _pk, _link, _contract, _instance_id} <- all_providers(host_id) do
      ProviderModule.halt(pid)
    end
  end

  @doc """
  Produces a list of tuples in the form of {pid, public_key, link_name, contract_id, instance_id}
  of all of the current providers running
  """
  def all_providers(host_id) do
    # $1 - {pk, link_name}
    # $2 - pid
    # $3 - host_id
    providers_on_host = providers_on_host(host_id)

    providers_on_host
    |> Enum.map(fn {{pk, link_name}, pid} ->
      {pid, pk, link_name, HostCore.Providers.ProviderModule.contract_id(pid),
       HostCore.Providers.ProviderModule.instance_id(pid)}
    end)
  end

  def find_provider(host_id, public_key, link_name) do
    pids =
      for {{pk, ln}, pid} <- providers_on_host(host_id),
          pk == public_key && link_name == ln do
        pid
      end

    List.first(pids)
  end

  defp providers_on_host(host_id) do
    Registry.select(
      Registry.ProviderRegistry,
      [{{:"$1", :"$2", :"$3"}, [{:==, :"$3", host_id}], [{{:"$1", :"$2"}}]}]
    )
  end

end
