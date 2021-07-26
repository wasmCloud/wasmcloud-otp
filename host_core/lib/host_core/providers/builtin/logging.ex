defmodule HostCore.Providers.Builtin.Logging do
  require Logger

  def invoke(actor, "WriteLog", payload) do
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