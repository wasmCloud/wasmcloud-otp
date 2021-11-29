defmodule HostCore.Providers.Builtin.Logging do
  @moduledoc false
  require Logger

  def invoke(actor, "Logging.WriteLog", payload, _api_version) do
    msg = Msgpax.unpack!(payload)
    text = "[#{actor}] #{msg["text"]}"

    case msg["level"] do
      "error" -> Logger.error(text)
      "info" -> Logger.info(text)
      "warn" -> Logger.warn(text)
      "debug" -> Logger.debug(text)
      _ -> Logger.debug(text)
    end

    nil
  end
end
