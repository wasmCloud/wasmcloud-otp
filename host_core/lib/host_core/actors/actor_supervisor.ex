defmodule HostCore.Actors.ActorSupervisor do
  use DynamicSupervisor
  alias HostCore.Actors.ActorModule
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
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
        {:stop, err}

      {:ok, claims} ->
        DynamicSupervisor.start_child(
          __MODULE__,
          {HostCore.Actors.ActorModule, {claims, bytes, oci}}
        )
    end
  end

  def start_actor_from_oci(oci) do
    # TODO use configuration for enabling insecure OCI and 'latest'
    case HostCore.WasmCloud.Native.get_oci_bytes(oci, false, []) do
      {:error, err} ->
        Logger.error("Failed to download OCI bytes for #{oci}")
        {:stop, err}

      {:ok, bytes} ->
        start_actor(bytes |> IO.iodata_to_binary(), oci)
    end
  end

  def live_update(oci) do
    with {:ok, bytes} <- HostCore.WasmCloud.Native.get_oci_bytes(oci, false, []),
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
        HostCore.Actors.ActorModule.live_update(pid, bytes |> IO.iodata_to_binary(), new_claims)
      end)

      :ok
    else
      _err -> :error
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

  def find_actor(public_key) do
    Map.get(all_actors(), public_key, [])
  end

  @doc """
  Ensures that the actor count is equal to the desired count by terminating instances
  or starting instances on the host.
  """
  def scale_actor(public_key, desired_count) do
    current_count = find_actor(public_key) |> Enum.count()

    diff = current_count - desired_count
    IO.puts("trying to scale")
    IO.inspect(current_count)
    IO.inspect(desired_count)
    IO.inspect(diff)

    cond do
      # Current count is desired actor count
      diff == 0 ->
        {:ok}

      # Current count is greater than desired count, terminate instances
      diff > 0 ->
        terminate_actor(public_key, diff)

      # Current count is less than desired count, start more instances
      diff < 0 ->
        {"need to start actor"}
    end
  end

  def terminate_actor(public_key, count) when count > 0 do
    children =
      Registry.lookup(Registry.ActorRegistry, public_key)
      |> Enum.take(count)
      |> Enum.map(fn {pid, _v} -> pid end)

    children |> Enum.each(fn pid -> ActorModule.halt(pid) end)

    {:ok}
  end

  def terminate_actor(_public_key, 0) do
    {:ok}
  end

  def terminate_all() do
    all_actors()
    |> Enum.map(fn {k, v} -> {k, Enum.count(v)} end)
    |> Enum.each(fn {pk, count} -> terminate_actor(pk, count) end)
  end
end
