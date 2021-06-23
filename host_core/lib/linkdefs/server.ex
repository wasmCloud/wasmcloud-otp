defmodule HostCore.Linkdefs.Server do
  require Logger
  use Gnat.Server

  def request(%{topic: topic, body: body}) do
    ld = Msgpax.unpack!(body)
    cmd = topic |> String.split(".") |> Enum.at(6)
    key = {ld["actor_id"], ld["contract_id"], ld["link_name"]}
    map = %{values: ld["values"], provider_key: ld["provider_id"]}

    Logger.info("Received link definition command (#{cmd})")

    if cmd == "put" do
      :ets.insert(:linkdef_table, {key, map})
      :ok
      # else if cmd == "get" do
      # {:reply, linkdefs}
    else
      :ets.delete(:linkdef_table, key)
      :ok
    end
  end
end
