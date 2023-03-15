defmodule HostCore.WasmCloud.Runtime.Config do
  @moduledoc ~S"""
  Configures a `WasmCloud.Runtime`.

  ## Options
    * `:placeholder` - holds a place

  ## Example
      iex> _config = %HostCore.WasmCloud.Runtime.Config{}
  """

  defstruct placeholder: false

  @type t :: %__MODULE__{
          placeholder: boolean()
        }
end
