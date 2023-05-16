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
  alias HostCore.CloudEvent
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
          count :: integer(),
          annotations :: map()
        ) :: {:error, any} | {:ok, [pid()]}
  def start_actor(bytes, host_id, oci \\ "", count \\ 1, annotations \\ %{})
      when is_binary(bytes) do
    Tracer.with_span "Starting Actor" do
      Tracer.set_attribute("actor_ref", oci)
      Tracer.set_attribute("host_id", host_id)
      Tracer.set_attribute("byte_size", byte_size(bytes))
      Logger.debug("Start actor request received for #{oci}", oci_ref: oci)

      source = HostCore.Policy.Manager.default_source()
      claims_result = get_claims(bytes, oci)

      # If we can't lookup the host ID, we can't start the actor. Shouldn't
      # reach this point but just in case.
      host_pid =
        case VirtualHost.lookup(host_id) do
          {:ok, {pid, _config}} -> pid
          :error -> nil
        end

      config = VirtualHost.config(host_pid)
      labels = VirtualHost.labels(host_pid)

      with true <- is_pid(host_pid),
           # Reversed boolean here so we can catch the error in one else block
           true <- !is_nil(config),
           {:ok, claims} <- claims_result,
           target <- %{
             publicKey: claims.public_key,
             issuer: claims.issuer,
             contractId: nil,
             linkName: nil
           },
           # Validate policy
           %{permitted: true} <-
             HostCore.Policy.Manager.evaluate_action(config, labels, source, target, @start_actor),
           # Ensure no other OCI reference is running for this actor ID
           {:ok} <- check_other_oci_already_running(oci, claims.public_key, host_id),
           # Start actors
           pids <- start_actor_instances(claims, bytes, oci, annotations, host_id, count) do
        Tracer.add_event("Actor(s) Started", [])
        Tracer.set_status(:ok, "")

        publish_actors_started(
          claims,
          oci,
          annotations,
          pids |> length(),
          host_id,
          config.lattice_prefix
        )

        {:ok, pids}
      else
        # Could not lookup host or config by ID
        false ->
          error = "Host not found"
          Tracer.set_status(:error, error)

          {:error, "Failed to find host #{host_id}"}

        # Policy server denied starting actor
        %{permitted: false, message: message, requestId: request_id} ->
          error = "Policy denied starting actor, request: #{request_id}"
          Tracer.set_status(:error, error)

          public_key = public_key_from_claims_result(claims_result)

          publish_actors_start_failed(
            public_key,
            oci,
            annotations,
            host_id,
            config.lattice_prefix,
            error
          )

          {:error, "Starting actor denied: #{message}"}

        # Error extracting claims or starting actor after passing validation
        {:error, err} ->
          error = "#{inspect(err)}"
          Tracer.set_status(:error, error)

          public_key = public_key_from_claims_result(claims_result)

          publish_actors_start_failed(
            public_key,
            oci,
            annotations,
            host_id,
            config.lattice_prefix,
            error
          )

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

  @spec public_key_from_claims_result(
          claims :: {:ok, claims :: map()} | {:error, error :: binary()}
        ) :: binary()
  defp public_key_from_claims_result(claims) do
    case claims do
      {:ok, claims} -> claims.public_key
      {:error, _error} -> "N/A"
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

  @spec start_actor_instances(
          claims :: map(),
          bytes :: binary(),
          oci :: binary(),
          annotations :: map(),
          host_id :: binary(),
          count :: non_neg_integer()
        ) :: list()
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

  def start_actor_from_ref(host_id, ref, count \\ 1, annotation \\ %{}) do
    cond do
      String.starts_with?(ref, "bindle://") ->
        start_actor_from_bindle(host_id, ref, count, annotation)

      String.starts_with?(ref, "file://") ->
        start_actor_from_file(host_id, ref, count, annotation)

      true ->
        start_actor_from_oci(host_id, ref, count, annotation)
    end
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

  def start_actor_from_file(host_id, fileref, count \\ 1, annotations \\ %{}) do
    config = VirtualHost.config(host_id)

    if config.enable_actor_from_fs do
      Tracer.with_span "Starting Actor from file", kind: :server do
        case File.read(String.trim_leading(fileref, "file://")) do
          {:error, err} ->
            Tracer.add_event("file read failed", reason: "#{inspect(err)}")

            Logger.error(
              "Failed to read actor file from ${fileref}: #{inspect(err)}",
              fileref: fileref
            )

            {:error, err}

          {:ok, binary} ->
            binary
            |> start_actor(host_id, fileref, count, annotations)
        end
      end
    else
      {:error, "actor file loading is disabled"}
    end
  end

  def live_update(host_id, ref, span_ctx \\ nil) do
    {:ok, {pid, lattice_prefix}} = VirtualHost.lookup(host_id)
    config = VirtualHost.config(pid)

    if String.starts_with?(ref, "file://") do
      if not config.enable_actor_from_fs do
        {:error, "actor from local filesystem is disabled"}
      else
        with {:ok, binary} <- File.read(String.trim_leading(ref, "file://")),
             {:ok, new_claims} <- Native.extract_claims(binary),
             {:ok, old_claims} <-
               HostCore.Claims.Manager.lookup_claims(lattice_prefix, new_claims.public_key),
             :ok <- validate_actor_for_update(old_claims, new_claims) do
          HostCore.Claims.Manager.put_claims(host_id, lattice_prefix, new_claims)

          HostCore.Refmaps.Manager.put_refmap(
            host_id,
            lattice_prefix,
            ref,
            new_claims.public_key
          )

          targets = find_actor(new_claims.public_key, host_id)

          Logger.info("Performing live update on #{length(targets)} instances",
            actor_id: new_claims.public_key,
            oci_ref: ref
          )

          Enum.each(targets, fn pid ->
            ActorModule.live_update(
              config,
              pid,
              binary,
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
    else
      creds = VirtualHost.get_creds(host_id, :oci, ref)

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
  @spec all_actors_for_hb(host_id :: String.t()) :: %{String.t() => integer()}
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
        start_actor_from_ref(host_id, ociref, abs(diff))

      true ->
        Tracer.set_status(:error, "Not allowed to scale actor w/out OCI reference")
        {:error, "Scaling actor up without an OCI reference is not currently supported"}
    end
  end

  # Terminate `count` instances of an actor
  @spec terminate_actor(
          host_id :: binary(),
          public_key :: binary(),
          count :: non_neg_integer(),
          annotations :: map()
        ) :: :ok
  def terminate_actor(host_id, public_key, count, annotations) when count > 0 do
    remaining = halt_required_actors(host_id, public_key, annotations, count)

    lattice_prefix = VirtualHost.get_lattice_for_host(host_id)
    publish_actors_stopped(host_id, public_key, lattice_prefix, count, remaining, annotations)

    if remaining <= 0 do
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

  @spec publish_actors_started(
          claims :: %{
            :call_alias => any,
            :caps => any,
            :expires_human => any,
            :issuer => any,
            :name => any,
            :not_before_human => any,
            :public_key => any,
            :revision => any,
            :tags => any,
            :version => any
          },
          oci :: String.t(),
          annotations :: map(),
          count :: non_neg_integer(),
          host_id :: String.t(),
          lattice_prefix :: String.t()
        ) :: :ok
  def publish_actors_started(claims, oci, annotations, count, host_id, lattice_prefix) do
    %{
      public_key: claims.public_key,
      image_ref: oci,
      annotations: annotations,
      host_id: host_id,
      claims: %{
        call_alias: claims.call_alias,
        caps: claims.caps,
        issuer: claims.issuer,
        tags: claims.tags,
        name: claims.name,
        version: claims.version,
        revision: claims.revision,
        not_before_human: claims.not_before_human,
        expires_human: claims.expires_human
      },
      count: count
    }
    |> CloudEvent.new("actors_started", host_id)
    |> CloudEvent.publish(lattice_prefix)
  end

  @spec publish_actors_start_failed(
          public_key :: String.t(),
          oci :: String.t(),
          annotations :: map(),
          host_id :: String.t(),
          lattice_prefix :: String.t(),
          error :: String.t()
        ) :: :ok
  def publish_actors_start_failed(public_key, oci, annotations, host_id, lattice_prefix, error) do
    %{
      public_key: public_key,
      image_ref: oci,
      annotations: annotations,
      host_id: host_id,
      error: error
    }
    |> CloudEvent.new("actors_start_failed", host_id)
    |> CloudEvent.publish(lattice_prefix)
  end

  @spec publish_actors_stopped(
          host_id :: String.t(),
          public_key :: String.t(),
          lattice_prefix :: String.t(),
          count :: non_neg_integer(),
          remaining :: non_neg_integer(),
          annotations :: map()
        ) :: :ok
  def publish_actors_stopped(host_id, public_key, lattice_prefix, count, remaining, annotations) do
    %{
      host_id: host_id,
      public_key: public_key,
      count: count,
      remaining: remaining,
      annotations: annotations
    }
    |> CloudEvent.new("actors_stopped", host_id)
    |> CloudEvent.publish(lattice_prefix)
  end
end
