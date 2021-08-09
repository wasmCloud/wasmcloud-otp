defmodule HostCore.Oci do
  def allow_latest() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:allow_latest]
      _ -> false
    end
  end

  def allowed_insecure() do
    case :ets.lookup(:config_table, :config) do
      [config: config_map] -> config_map[:allowed_insecure]
      _ -> []
    end
  end
end
