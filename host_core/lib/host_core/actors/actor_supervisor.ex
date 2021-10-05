defmodule HostCore.Actors.ActorSupervisor do
  @moduledoc false
  use DynamicSupervisor
  alias HostCore.Actors.ActorModule
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_actor(binary) ::
          :ignore | {:error, any} | {:ok, pid} | {:stop, any} | {:ok, pid, any}
  def start_actor(bytes, oci \\ "") when is_binary(bytes) do
    Logger.info("Starting actor")

    case HostCore.WasmCloud.Native.extract_claims(bytes) do
      {:error, err} ->
        Logger.error("Failed to extract claims from WebAssembly module")
        {:error, err}

      {:ok, claims} ->
        if other_oci_already_running?(oci, claims.public_key) do
          {:error,
           "Cannot start new instance of #{claims.public_key} from OCI '#{oci}', it is already running with different OCI reference. To upgrade an actor, use live update."}
        else
          DynamicSupervisor.start_child(
            __MODULE__,
            {HostCore.Actors.ActorModule, {claims, bytes, oci}}
          )
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

  def start_actor_from_oci(oci) do
    case HostCore.WasmCloud.Native.get_oci_bytes(
           oci,
           HostCore.Oci.allow_latest(),
           HostCore.Oci.allowed_insecure()
         ) do
      {:error, err} ->
        Logger.error("Failed to download OCI bytes for #{oci}")
        {:stop, err}

      {:ok, bytes} ->
        start_actor(bytes |> IO.iodata_to_binary(), oci)
    end
  end

  def live_update(oci) do
    with {:ok, bytes} <-
           HostCore.WasmCloud.Native.get_oci_bytes(
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
      Logger.info("Performing live update on #{length(targets)} instances")

      targets
      |> Enum.each(fn pid ->
        HostCore.Actors.ActorModule.live_update(
          pid,
          bytes |> IO.iodata_to_binary(),
          new_claims,
          oci
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
        case 1..abs(diff)
             |> Enum.reduce_while("", fn _, _ ->
               case start_actor_from_oci(ociref) do
                 {:stop, err} ->
                   {:halt, "Error: #{err}"}

                 {:error, err} ->
                   {:halt, "Error: #{err}"}

                 _any ->
                   {:cont, ""}
               end
             end) do
          "" -> :ok
          err -> {:error, err}
        end

      diff < 0 ->
        {:error, "Scaling actor up without an OCI reference is not currently supported"}
    end
  end

  def terminate_actor(public_key, count) when count > 0 do
    children =
      Registry.lookup(Registry.ActorRegistry, public_key)
      |> Enum.take(count)
      |> Enum.map(fn {pid, _v} -> pid end)

    children |> Enum.each(fn pid -> ActorModule.halt(pid) end)

    :ok
  end

  def terminate_actor(_public_key, 0) do
    :ok
  end

  def terminate_all() do
    all_actors()
    |> Enum.map(fn {k, v} -> {k, Enum.count(v)} end)
    |> Enum.each(fn {pk, count} -> terminate_actor(pk, count) end)
  end
end
