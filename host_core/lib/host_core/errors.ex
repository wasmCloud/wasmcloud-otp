defmodule HostCore.ConfigFileFormatNotFoundError do
  defexception [:message]

  @impl true
  def exception(path) do
    msg = "configuration file: #{path} is not a registered file format"
    %__MODULE__{message: msg}
  end
end
