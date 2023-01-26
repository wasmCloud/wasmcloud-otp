defmodule HostCore.Actors.ActorSupervisor do
  @moduledoc """
  The supervisor module for actor modules. It is responsible for starting, stopping, restarting, and all other aspects
  of managing actor (wasm component) instances. Do not attempt to start or stop the actor modules on your own, always
  go through this module to ensure consistent behavior.
  """
  use DynamicSupervisor

  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  alias HostCore.Actors.ActorModule
  alias HostCore.Actors.ActorRpcSupervisor
  alias HostCore.Vhost.VirtualHost
  alias HostCore.WasmCloud.Native

  @start_actor "start_actor"

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_actor(
          bytes :: binary(),
          host_id :: String.t(),
          oci :: String.t(),
          count :: Integer.t(),
          annotations :: Map.t()
        ) :: {:error, any} | {:ok, [pid()]}
  def start_actor(bytes, host_id, oci \\ "", count \\ 1, annotations \\ %{})
      when is_binary(bytes) do
    Tracer.with_span "Starting Actor" do
      Tracer.set_attribute("actor_ref", oci)
      Tracer.set_attribute("host_id", host_id)
      Tracer.set_attribute("byte_size", byte_size(bytes))
      Logger.debug("Start actor request received for #{oci}", oci_ref: oci)

      source = HostCore.Policy.Manager.default_source()

      with {:ok, {pid, _}} <- VirtualHost.lookup(host_id),
           config <- VirtualHost.config(pid),
           labels <- VirtualHost.labels(pid),
           {:ok, claims} <- get_claims(bytes, oci),
           target <- %{
             publicKey: claims.public_key,
             issuer: claims.issuer,
             contractId: nil,
             linkName: nil
           },
           %{permitted: true} <-
             HostCore.Policy.Manager.evaluate_action(config, labels, source, target, @start_actor),
           {:ok} <- check_other_oci_already_running(oci, claims.public_key, host_id),
           pids <- start_actor_instances(claims, bytes, oci, annotations, host_id, count) do
        Tracer.add_event("Actor(s) Started", [])
        Tracer.set_status(:ok, "")
        {:ok, pids}
      else
        %{permitted: false, message: message, requestId: request_id} ->
          Tracer.set_status(:error, "Policy denied starting actor, request: #{request_id}")
          {:error, "Starting actor denied: #{message}"}

        :error ->
          Tracer.set_status(:error, "Host not found")
          {:error, "Failed to find host #{host_id}"}

        {:error, err} ->
          Tracer.set_status(:error, "#{inspect(err)}")
          {:error, err}
      end
    end
  end

  defp get_claims(bytes, oci) do
    case Native.extract_claims(bytes) do
      {:error, err} ->
        Logger.error(
          "Failed to extract claims from WebAssembly module, an actor must be signed with valid capability claims. (#{byte_size(bytes)} bytes)",
          oci_ref: oci
        )

        {:error, err}

      {:ok, claims} ->
        {:ok, claims}
    end
  end

  # Returns whether the given actor's public key has at least one
  # OCI reference running _other_ than the candidate supplied.
  defp check_other_oci_already_running(oci, pk, host_id) do
    case Enum.any?(
           host_ocirefs(host_id),
           fn {_pid, other_pk, other_oci} -> other_pk == pk && other_oci != oci end
         ) do
      true ->
        {:error,
         "Cannot start new instance of #{pk} from ref '#{oci}', it is already running with different reference. To upgrade an actor, use live update."}

      false ->
        {:ok}
    end
  end

  defp start_actor_instances(claims, bytes, oci, annotations, host_id, count) do
    # Start `count` instances of this actor
    opts = %{
      claims: claims,
      bytes: bytes,
      oci: oci,
      annotations: annotations,
      host_id: host_id
    }

    Enum.reduce_while(1..count, [], fn _count, pids ->
      case DynamicSupervisor.start_child(
             __MODULE__,
             {ActorModule, opts}
           ) do
        {:error, err} ->
          Logger.error("Failed to start actor instance", err)
          {:halt, {:error, "Error: #{inspect(err)}"}}

        {:ok, pid} ->
          {:cont, [pid | pids]}

        {:ok, pid, _info} ->
          {:cont, [pid | pids]}

        :ignore ->
          {:cont, pids}
      end
    end)
  end

  def start_actor_from_oci(host_id, ref, count \\ 1, annotations \\ %{}) do
    Tracer.with_span "Starting Actor from OCI", kind: :server do
      Tracer.set_attribute("host_id", host_id)
      Tracer.set_attribute("oci_ref", ref)

      creds = VirtualHost.get_creds(host_id, :oci, ref)
      {:ok, {pid, _prefix}} = VirtualHost.lookup(host_id)
      config = VirtualHost.config(pid)

      case Native.get_oci_bytes(
             creds,
             ref,
             config.allow_latest,
             config.allowed_insecure
           ) do
        {:error, err} ->
          Tracer.add_event("OCI image fetch failed", reason: "#{inspect(err)}")
          Tracer.set_status(:error, "#{inspect(err)}")

          Logger.error("Failed to download OCI bytes from \"#{ref}\": #{inspect(err)}",
            oci_ref: ref
          )

          {:error, err}

        {:ok, bytes} ->
          Tracer.add_event("OCI image fetched", byte_size: length(bytes))

          bytes
          |> IO.iodata_to_binary()
          |> start_actor(host_id, ref, count, annotations)
      end
    end
  end

  def start_actor_from_bindle(host_id, bindle_id, count \\ 1, annotations \\ %{}) do
    Tracer.with_span "Starting Actor from Bindle", kind: :server do
      creds = VirtualHost.get_creds(host_id, :bindle, bindle_id)

      case Native.get_actor_bindle(
             creds,
             String.trim_leading(bindle_id, "bindle://")
           ) do
        {:error, err} ->
          Tracer.add_event("Bindle fetch failed", reason: "#{inspect(err)}")

          Logger.error(
            "Failed to download bytes from bindle server for #{bindle_id}: #{inspect(err)}",
            bindle_id: bindle_id
          )

          {:error, err}

        {:ok, bytes} ->
          Tracer.add_event("Bindle fetched", byte_size: length(bytes))

          bytes
          |> IO.iodata_to_binary()
          |> start_actor(host_id, bindle_id, count, annotations)
      end
    end
  end

  def live_update(host_id, ref, span_ctx \\ nil) do
    creds = VirtualHost.get_creds(host_id, :oci, ref)
    {:ok, {pid, lattice_prefix}} = VirtualHost.lookup(host_id)
    config = VirtualHost.config(pid)

    with {:ok, bytes} <-
           Native.get_oci_bytes(
             creds,
             ref,
             config.allow_latest,
             config.allowed_insecure
           ),
         {:ok, new_claims} <-
           bytes |> IO.iodata_to_binary() |> Native.extract_claims(),
         {:ok, old_claims} <-
           HostCore.Claims.Manager.lookup_claims(lattice_prefix, new_claims.public_key),
         :ok <- validate_actor_for_update(old_claims, new_claims) do
      HostCore.Claims.Manager.put_claims(host_id, lattice_prefix, new_claims)
      HostCore.Refmaps.Manager.put_refmap(host_id, lattice_prefix, ref, new_claims.public_key)
      targets = find_actor(new_claims.public_key, host_id)

      Logger.info("Performing live update on #{length(targets)} instances",
        actor_id: new_claims.public_key,
        oci_ref: ref
      )

      # Each spawned function is a new process, therefore a new root trace
      # this is why we pass the span context so all child updates roll up
      # to the current trace
      Enum.each(targets, fn pid ->
        ActorModule.live_update(
          config,
          pid,
          IO.iodata_to_binary(bytes),
          new_claims,
          ref,
          span_ctx
        )
      end)

      :ok
    else
      err -> {:error, err}
    end
  end

  defp validate_actor_for_update(%{rev: rev}, %{revision: new_rev}) do
    case Integer.parse(rev) do
      {old_rev, _} ->
        if new_rev > old_rev, do: :ok, else: :error

      _ ->
        :error
    end
  end

  @doc """
  Produces a map with the key being the public key of the actor and the value being a _list_
  of all of the pids (running instances) of that actor.
  """
  def all_actors(host_id) do
    Registry.ActorRegistry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [{:==, :"$3", host_id}], [{{:"$1", :"$2"}}]}])
    |> Enum.group_by(
      fn {h, _p} -> h end,
      fn {_h, p} -> p end
    )
  end

  @doc """
  A slightly different version of the all actors list, formatted for
  suitability on emitted heartbeats. Maps the public key of the actor
  to the count of instances
  """
  @spec all_actors_for_hb(host_id :: String.t()) :: %{String.t() => Integer.t()}
  def all_actors_for_hb(host_id) do
    # $1 - pk
    # $2 - pid
    # $3 - host_id
    actors_on_host =
      Registry.select(Registry.ActorRegistry, [
        {{:"$1", :"$2", :"$3"}, [{:==, :"$3", host_id}], [{{:"$1", :"$2"}}]}
      ])

    Enum.reduce(actors_on_host, %{}, fn {pk, _pid}, acc -> Map.update(acc, pk, 1, &(&1 + 1)) end)
  end

  @doc """
  Produces a list of tuples containing the pid of the child actor, its public key, and its
  OCI reference.
  """
  def host_ocirefs(host_id) do
    for {pk, pids} <- all_actors(host_id),
        pid <- pids,
        do: {pid, pk, ActorModule.ociref(pid)}
  end

  @spec find_actor(public_key :: String.t(), host_id :: String.t()) :: [pid()]
  def find_actor(public_key, host_id) do
    Map.get(all_actors(host_id), public_key, [])
  end

  @doc """
  Ensures that the actor count is equal to the desired count by terminating instances
  or starting instances on the host.
  """
  def scale_actor(host_id, public_key, desired_count, oci \\ "") do
    current_instances = find_actor(public_key, host_id)
    current_count = Enum.count(current_instances)

    # Attempt to retrieve OCI reference from running actor if not supplied
    ociref =
      cond do
        oci != "" ->
          oci

        current_count >= 1 ->
          current_instances |> List.first() |> ActorModule.ociref()

        true ->
          ""
      end

    diff = current_count - desired_count

    cond do
      # Current count is desired actor count
      diff == 0 ->
        :ok

      # Current count is greater than desired count, terminate instances
      diff > 0 ->
        # wadm won't use the scale actor call, so we don't care about annotations here
        terminate_actor(host_id, public_key, diff, %{})

      # Current count is less than desired count, start more instances
      diff < 0 && ociref != "" ->
        if String.starts_with?(ociref, "bindle://") do
          start_actor_from_bindle(host_id, ociref, abs(diff))
        else
          start_actor_from_oci(host_id, ociref, abs(diff))
        end

      true ->
        Tracer.set_status(:error, "Not allowed to scale actor w/out OCI reference")
        {:error, "Scaling actor up without an OCI reference is not currently supported"}
    end
  end

  # Terminate `count` instances of an actor
  def terminate_actor(host_id, public_key, count, annotations) when count > 0 do
    remaining = halt_required_actors(host_id, public_key, annotations, count)

    if remaining <= 0 do
      lattice_prefix = VirtualHost.get_lattice_for_host(host_id)
      ActorRpcSupervisor.stop_rpc_subscriber(lattice_prefix, public_key)
    end

    :ok
  end

  # Terminate all instances of an actor
  def terminate_actor(host_id, public_key, 0, annotations) do
    lattice_prefix = VirtualHost.get_lattice_for_host(host_id)
    actors = find_actor(public_key, host_id)
    halt_required_actors(host_id, public_key, annotations, length(actors))

    ActorRpcSupervisor.stop_rpc_subscriber(lattice_prefix, public_key)

    :ok
  end

  def terminate_all(host_id) do
    for {k, v} <- all_actors(host_id),
        count = Enum.count(v),
        do: halt_required_actors(host_id, k, %{}, count)
  end

  defp halt_required_actors(host_id, public_key, annotations, count) do
    actors = find_actor(public_key, host_id)
    remaining = length(actors) - count

    for pid <- Enum.take(actors, count),
        existing = get_annotations(pid),
        Map.merge(existing, annotations) == existing,
        do: ActorModule.halt(pid)

    remaining
  end

  defp get_annotations(pid), do: ActorModule.annotations(pid)
end
