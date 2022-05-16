defmodule HostCore.Actors.ActorSupervisor do
  @moduledoc false
  use DynamicSupervisor
  alias HostCore.Actors.ActorModule
  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_actor(
          bytes :: binary(),
          oci :: String.t(),
          count :: Integer.t(),
          annotations :: Map.t()
        ) :: {:error, any} | {:ok, [pid()]}
  def start_actor(bytes, oci \\ "", count \\ 1, annotations \\ %{}) when is_binary(bytes) do
    Tracer.with_span "Starting Actor" do
      Tracer.set_attribute("actor_ref", oci)
      Tracer.set_attribute("byte_size", byte_size(bytes))
      Logger.debug("Start actor request received", oci_ref: oci)

      case HostCore.WasmCloud.Native.extract_claims(bytes) do
        {:error, err} ->
          Tracer.set_status(:error, "#{inspect(err)}")
          Logger.error("Failed to extract claims from WebAssembly module", oci_ref: oci)
          {:error, err}

        {:ok, claims} ->
          if other_oci_already_running?(oci, claims.public_key) do
            Tracer.set_status(:error, "Already running")

            {:error,
             "Cannot start new instance of #{claims.public_key} from OCI '#{oci}', it is already running with different OCI reference. To upgrade an actor, use live update."}
          else
            # Start `count` instances of this actor
            case 1..count
                 |> Enum.reduce_while([], fn _count, pids ->
                   case DynamicSupervisor.start_child(
                          __MODULE__,
                          {HostCore.Actors.ActorModule, {claims, bytes, oci, annotations}}
                        ) do
                     {:error, err} ->
                       {:halt, {:error, "Error: #{err}"}}

                     {:ok, pid} ->
                       {:cont, [pid | pids]}

                     {:ok, pid, _info} ->
                       {:cont, [pid | pids]}

                     :ignore ->
                       {:cont, pids}
                   end
                 end) do
              {:error, err} ->
                Tracer.set_status(:error, "#{inspect(err)}")
                {:error, err}

              pids ->
                Tracer.add_event("Actor(s) Started", [])
                Tracer.set_status(:ok, "")
                {:ok, pids}
            end
          end
      end
    end
  end

  # Returns whether the given actor's public key has at least one
  # OCI reference running _other_ than the candidate supplied.
  defp other_oci_already_running?(coci, pk) do
    child_ocirefs()
    |> Enum.filter(fn {_pid, tpk, toci} -> tpk == pk && toci != coci end)
    |> length() > 0
  end

  def start_actor_from_oci(oci, count \\ 1, annotations \\ %{}) do
    Tracer.with_span "Starting Actor from OCI", kind: :server do
      creds = HostCore.Host.get_creds(oci)

      case HostCore.WasmCloud.Native.get_oci_bytes(
             creds,
             oci,
             HostCore.Oci.allow_latest(),
             HostCore.Oci.allowed_insecure()
           ) do
        {:error, err} ->
          Tracer.add_event("OCI image fetch failed", reason: "#{inspect(err)}")
          Tracer.set_status(:error, "#{inspect(err)}")
          Logger.error("Failed to download OCI bytes for #{oci}: #{inspect(err)}", oci_ref: oci)
          {:error, err}

        {:ok, bytes} ->
          Tracer.add_event("OCI image fetched", byte_size: length(bytes))
          start_actor(bytes |> IO.iodata_to_binary(), oci, count, annotations)
      end
    end
  end

  def start_actor_from_bindle(bindle_id, count \\ 1, annotations \\ %{}) do
    Tracer.with_span "Starting Actor from Bindle", kind: :server do
      creds = HostCore.Host.get_creds(bindle_id)

      case HostCore.WasmCloud.Native.get_actor_bindle(
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
          start_actor(bytes |> IO.iodata_to_binary(), bindle_id, count, annotations)
      end
    end
  end

  def live_update(oci, span_ctx \\ nil) do
    creds = HostCore.Host.get_creds(oci)

    with {:ok, bytes} <-
           HostCore.WasmCloud.Native.get_oci_bytes(
             creds,
             oci,
             HostCore.Oci.allow_latest(),
             HostCore.Oci.allowed_insecure()
           ),
         {:ok, new_claims} <-
           HostCore.WasmCloud.Native.extract_claims(bytes |> IO.iodata_to_binary()),
         {:ok, old_claims} <- HostCore.Claims.Manager.lookup_claims(new_claims.public_key),
         :ok <- validate_actor_for_update(old_claims, new_claims) do
      HostCore.Claims.Manager.put_claims(new_claims)
      HostCore.Refmaps.Manager.put_refmap(oci, new_claims.public_key)
      targets = find_actor(new_claims.public_key)

      Logger.info("Performing live update on #{length(targets)} instances",
        actor_id: new_claims.public_key,
        oci_ref: oci
      )

      # Each spawned function is a new process, therefore a new root trace
      # this is why we pass the span context so all child updates roll up
      # to the current trace
      targets
      |> Enum.each(fn pid ->
        HostCore.Actors.ActorModule.live_update(
          pid,
          bytes |> IO.iodata_to_binary(),
          new_claims,
          oci,
          span_ctx
        )
      end)

      :ok
    else
      err -> {:error, err}
    end
  end

  defp validate_actor_for_update({_pk, old_claims}, new_claims) do
    {old_rev, _} = Integer.parse(old_claims.rev)
    new_rev = new_claims.revision

    if new_rev > old_rev do
      :ok
    else
      :error
    end
  end

  @doc """
  Produces a map with the key being the public key of the actor and the value being a _list_
  of all of the pids (running instances) of that actor.
  """
  def all_actors() do
    Supervisor.which_children(HostCore.Actors.ActorSupervisor)
    |> Enum.map(fn {_id, pid, _type_, _modules} ->
      {List.first(Registry.keys(Registry.ActorRegistry, pid)), pid}
    end)
    |> Enum.group_by(fn {k, _p} -> k end, fn {_k, p} -> p end)
  end

  @doc """
  A slightly different version of the all actors list, formatted for
  suitability on emitted heartbeats
  """
  def all_actors_for_hb() do
    Supervisor.which_children(HostCore.Actors.ActorSupervisor)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      {
        HostCore.Actors.ActorModule.claims(pid).public_key,
        HostCore.Actors.ActorModule.instance_id(pid)
      }
    end)
  end

  @doc """
  Produces a list of tuples containing the pid of the child actor, its public key, and its
  OCI reference.
  """
  def child_ocirefs() do
    Supervisor.which_children(HostCore.Actors.ActorSupervisor)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      {pid, HostCore.Actors.ActorModule.claims(pid).public_key,
       HostCore.Actors.ActorModule.ociref(pid)}
    end)
  end

  def find_actor(public_key) do
    Map.get(all_actors(), public_key, [])
  end

  @doc """
  Ensures that the actor count is equal to the desired count by terminating instances
  or starting instances on the host.
  """
  def scale_actor(public_key, desired_count, oci \\ "") do
    current_instances = find_actor(public_key)
    current_count = current_instances |> Enum.count()

    # Attempt to retrieve OCI reference from running actor if not supplied
    ociref =
      cond do
        oci != "" ->
          oci

        current_count >= 1 ->
          ActorModule.ociref(current_instances |> List.first())

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
        terminate_actor(public_key, diff)

      # Current count is less than desired count, start more instances
      diff < 0 && ociref != "" ->
        if String.starts_with?(ociref, "bindle://") do
          start_actor_from_bindle(ociref, abs(diff))
        else
          start_actor_from_oci(ociref, abs(diff))
        end

      diff < 0 ->
        Tracer.set_status(:error, "Not allowed to scale actor w/out OCI reference")
        {:error, "Scaling actor up without an OCI reference is not currently supported"}
    end
  end

  # Terminate `count` instances of an actor
  def terminate_actor(public_key, count) when count > 0 do
    Registry.lookup(Registry.ActorRegistry, public_key)
    |> Enum.take(count)
    |> Enum.map(fn {pid, _v} -> pid end)
    |> Enum.each(fn pid -> ActorModule.halt(pid) end)

    :ok
  end

  # Terminate all instances of an actor
  def terminate_actor(public_key, 0) do
    Registry.lookup(Registry.ActorRegistry, public_key)
    |> Enum.map(fn {pid, _v} -> pid end)
    |> Enum.each(fn pid -> ActorModule.halt(pid) end)

    :ok
  end

  def terminate_all() do
    all_actors()
    |> Enum.map(fn {k, v} -> {k, Enum.count(v)} end)
    |> Enum.each(fn {pk, count} -> terminate_actor(pk, count) end)
  end
end
