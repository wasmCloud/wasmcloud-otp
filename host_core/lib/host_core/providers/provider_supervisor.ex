defmodule HostCore.Providers.ProviderSupervisor do
  @moduledoc """
  The provider supervisor is the owner of provider processes. You should never attempt to start or stop individual `HostCore.Providers.ProviderModule` processes
  on your own. Instead you should use the appropriate start and stop functions on this supervisor. Additionally, if you need to obtain a list of running
  provider modules based on some criteria, you should use functions exposed by this supervisor rather than attempting to query the appropriate registry yourself
  """
  use DynamicSupervisor
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias HostCore.Providers.ProviderModule
  alias HostCore.Vhost.VirtualHost
  alias HostCore.WasmCloud.Native

  @start_provider "start_provider"
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_provider_from_ref(host_id, ref, link_name, config_json \\ "", annotations \\ %{}) do
    cond do
      String.starts_with?(ref, "bindle://") ->
        start_provider_from_bindle(host_id, ref, link_name, config_json, annotations)

      String.starts_with?(ref, "file://") ->
        start_provider_from_file(host_id, ref, link_name, annotations)

      true ->
        start_provider_from_oci(host_id, ref, link_name, config_json, annotations)
    end
  end

  @doc """
  Starts a capability provider from an OCI reference. This function requires you to pass the appropriate virtual host
  ID on which the provider will be started, along with the link name, startup configuration, and optional annotations typically
  used by wadm
  """
  @spec start_provider_from_oci(
          host_id :: String.t(),
          ref :: String.t(),
          link_name :: String.t(),
          config_json :: String.t(),
          annotations :: map()
        ) :: DynamicSupervisor.on_start_child()
  def start_provider_from_oci(host_id, ref, link_name, config_json \\ "", annotations \\ %{}) do
    Tracer.with_span "Start Provider from OCI" do
      creds = VirtualHost.get_creds(host_id, :oci, ref)
      config = VirtualHost.config(host_id)

      Tracer.set_attribute("oci_ref", ref)
      Tracer.set_attribute("link_name", link_name)
      Tracer.set_attribute("host_id", host_id)

      with {:ok, path} <-
             Native.get_oci_path(
               creds,
               ref,
               config.allow_latest,
               config.allowed_insecure
             ),
           {:ok, par} <-
             Native.par_from_path(
               path,
               link_name
             ) do
        Tracer.add_event("Provider fetched", [])

        start_executable_provider(
          host_id,
          Native.par_cache_path(
            par.claims.public_key,
            par.claims.revision,
            par.contract_id,
            link_name
          ),
          Map.put(par.claims, :contract_id, par.contract_id),
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

  @doc """
  Starts a capability provider from a bindle reference. Requires the public key of the virtual host on which
  the provider will be started as well as basic information like the bindle ID/reference, link name, startup configuration,
  and an optional map of annotations
  """
  @spec start_provider_from_bindle(
          host_id :: String.t(),
          bindle_id :: String.t(),
          link_name :: String.t(),
          config_json :: String.t(),
          annotations :: map()
        ) :: DynamicSupervisor.on_start_child()
  def start_provider_from_bindle(
        host_id,
        bindle_id,
        link_name,
        config_json \\ "",
        annotations \\ %{}
      ) do
    Tracer.with_span "Start Provider from Bindle" do
      creds = VirtualHost.get_creds(host_id, :bindle, bindle_id)

      Tracer.set_attribute("bindle_id", bindle_id)
      Tracer.set_attribute("link_name", link_name)
      Tracer.set_attribute("host_id", host_id)

      case Native.get_provider_bindle(
             creds,
             String.trim_leading(bindle_id, "bindle://"),
             link_name
           ) do
        {:ok, par} ->
          Tracer.add_event("Provider fetched", [])

          start_executable_provider(
            host_id,
            Native.par_cache_path(
              par.claims.public_key,
              par.claims.revision,
              par.contract_id,
              link_name
            ),
            Map.put(par.claims, :contract_id, par.contract_id),
            link_name,
            par.contract_id,
            bindle_id,
            config_json,
            annotations
          )

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

  @doc """
  Starts a capability provider from a local file. This function should only ever be invoked when the consumer is local, such as the washboard
  container application. This is never to be performed in production scenarios unless specific exceptions are made in the code.
  """
  @spec start_provider_from_file(
          host_id :: String.t(),
          path :: String.t(),
          link_name :: String.t(),
          annotations :: map()
        ) :: DynamicSupervisor.on_start_child()
  def start_provider_from_file(host_id, path, link_name, annotations \\ %{}) do
    Tracer.with_span "Start Provider from File" do
      case Native.par_from_path(path, link_name) do
        {:ok, par} ->
          start_executable_provider(
            host_id,
            Native.par_cache_path(
              par.claims.public_key,
              par.claims.revision,
              par.contract_id,
              link_name
            ),
            Map.put(par.claims, :contract_id, par.contract_id),
            link_name,
            par.contract_id,
            "",
            "",
            annotations
          )

        {:error, err} ->
          Logger.error("Error starting provider from file: #{err}", link_name: link_name)
          {:error, err}

        err ->
          Logger.error("Error starting provider from file: #{err}", link_name: link_name)
          {:error, err}
      end
    end
  end

  @doc """
  Used to query whether a capability provider identified by the public key, a reference URL (bindle/OCI), link name is
  running on the given virtual host
  """
  def provider_running?(host_id, reference, link_name, public_key) do
    lattice_prefix =
      case VirtualHost.lookup(host_id) do
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
    source = HostCore.Policy.Manager.default_source()

    target = %{
      publicKey: claims.public_key,
      issuer: claims.issuer,
      linkName: link_name,
      contractId: contract_id
    }

    with {:ok, {pid, _}} <- VirtualHost.lookup(host_id),
         full_state <- VirtualHost.full_state(pid),
         %{permitted: true} <-
           HostCore.Policy.Manager.evaluate_action(
             full_state.config,
             full_state.labels,
             source,
             target,
             @start_provider
           ),
         false <- provider_running?(host_id, oci, link_name, claims.public_key) do
      opts = %{
        path: path,
        claims: claims,
        link_name: link_name,
        lattice_prefix: full_state.config.lattice_prefix,
        contract_id: contract_id,
        oci: oci,
        config_json: config_json,
        host_id: host_id,
        shutdown_delay: full_state.config.provider_delay,
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

      true ->
        {:error, "Provider is already running on this host"}

      {:error, err} ->
        Tracer.set_status(:error, "#{inspect(err)}")
        {:error, err}
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
    host_id
    |> providers_on_host()
    |> Enum.map(fn {{pk, link_name}, pid} ->
      {pid, pk, link_name, ProviderModule.contract_id(pid), ProviderModule.instance_id(pid)}
    end)
  end

  @doc """
  Produces a list of maps, one for reach running provider on the host
  """
  @spec all_providers_for_hb(host_id :: String.t()) :: [
          %{
            required(:public_key) => String.t(),
            required(:link_name) => String.t()
          }
        ]
  def all_providers_for_hb(host_id) do
    providers_on_host = providers_on_host(host_id)
    lattice_prefix = HostCore.Vhost.VirtualHost.get_lattice_for_host(host_id)

    Enum.map(providers_on_host, fn {{pk, link_name}, _pid} ->
      contract_id =
        case HostCore.Claims.Manager.lookup_claims(lattice_prefix, pk) do
          {:ok, claims} ->
            Map.get(claims, :contract_id, "n/a")

          _ ->
            "n/a"
        end

      %{
        public_key: pk,
        link_name: link_name,
        contract_id: contract_id
      }
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
