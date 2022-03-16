defmodule HostCore.Providers.Builtin.Logging do
  @moduledoc false
  require Logger

  def invoke(actor, "Logging.WriteLog", payload) do
    msg = Msgpax.unpack!(payload)
    text = "[#{actor}] #{msg["text"]}"

    case msg["level"] do
      "error" -> Logger.error(text, actor_id: actor)
      "info" -> Logger.info(text, actor_id: actor)
      "warn" -> Logger.warn(text, actor_id: actor)
      "debug" -> Logger.debug(text, actor_id: actor)
      _ -> Logger.debug(text, actor_id: actor)
    end

    nil
  end
end
