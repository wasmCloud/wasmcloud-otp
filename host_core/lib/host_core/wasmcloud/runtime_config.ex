defmodule HostCore.WasmCloud.Runtime.Config do
  @moduledoc ~S"""
  Configures a `WasmCloud.Runtime`.

  ## Options
    * `:placeholder` - holds a place

  ## Example
      iex> _config = %HostCore.WasmCloud.Runtime.Config{}
  """

  defstruct host_id: ""

  @type t :: %__MODULE__{
          host_id: binary()
        }
end
