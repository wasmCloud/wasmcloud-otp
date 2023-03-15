defmodule HostCore.WasmCloud.Runtime do
  @moduledoc """
  This module provides encapsulated access to the native NIF function calls exposed through the wasmcloud/native.ex interface
  This runtime module supports the Runtime.Server module and should _not_ be used directly by any code other than that module. This
  would be a private module, but Elixir doesn't allow selective access
  """
  @type t :: %__MODULE__{
          resource: binary(),
          reference: reference()
        }

  defstruct resource: nil,
            # The actual NIF store resource.
            # Normally the compiler will happily do stuff like inlining the
            # resource in attributes. This will convert the resource into an
            # empty binary with no warning. This will make that harder to
            # accidentally do.
            reference: nil

  def __wrap_resource__(resource) do
    %__MODULE__{
      resource: resource,
      reference: make_ref()
    }
  end

  defmodule ActorReference do
    @type t :: %__MODULE__{
            resource: binary(),
            reference: reference()
          }
    defstruct resource: nil,
              reference: nil

    def __wrap_resource__(resource) do
      %__MODULE__{
        resource: resource,
        reference: make_ref()
      }
    end
  end

  @doc ~S"""
  Creates a new `HostCore.WasmCloud.Runtime` with the specified options.
  ## Example
      iex> {:ok, _runtime} = HosrCore.WasmCloud.Runtime.new(%WasmCloud.RuntimeConfig{})
  """
  @spec new(HostCore.WasmCloud.Runtime.Config.t()) :: {:ok, __MODULE__.t()} | {:error, binary()}
  def new(%HostCore.WasmCloud.Runtime.Config{} = config) do
    case HostCore.WasmCloud.Native.runtime_new(config) do
      {:error, err} -> {:error, err}
      resource -> {:ok, __wrap_resource__(resource)}
    end
  end

  def start_actor(%__MODULE__{resource: rtresource}, bytes) do
    case HostCore.WasmCloud.Native.start_actor(rtresource, bytes) do
      {:error, err} -> {:error, err}
      resource -> {:ok, ActorReference.__wrap_resource__(resource)}
    end
  end

  def version(%__MODULE__{resource: resource}) do
    case HostCore.WasmCloud.Native.version(resource) do
      {:error, _err} -> "??"
      version -> version
    end
  end

  @spec call_actor(
          HostCore.WasmCloud.Runtime.ActorReference.t(),
          binary(),
          binary(),
          GenServer.from()
        ) :: :ok
  def call_actor(
        %HostCore.WasmCloud.Runtime.ActorReference{resource: actor_resource},
        operation,
        payload,
        from
      ) do
    HostCore.WasmCloud.Native.call_actor(actor_resource, operation, payload, from)
  end

  defimpl Inspect, for: HostCore.WasmCloud.Runtime do
    import Inspect.Algebra

    def inspect(dict, opts) do
      concat(["#HostCore.WasmCloud.Runtime<", to_doc(dict.reference, opts), ">"])
    end
  end
end
