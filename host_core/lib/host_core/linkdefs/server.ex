defmodule HostCore.Linkdefs.Server do
  require Logger
  use Gnat.Server

  # wasmbus.rpc.#{prefix}.linkdefs.#{cmd}
  def request(%{topic: topic, body: body}) do
    cmd = topic |> String.split(".") |> Enum.at(4)
    Logger.info("Received link definition command (#{cmd})")

    case cmd do
      "put" ->
        ld = Msgpax.unpack!(body)

        HostCore.Linkdefs.Manager.cache_link_definition(
          ld["actor_id"],
          ld["contract_id"],
          ld["link_name"],
          ld["provider_id"],
          ld["values"]
        )

        :ok

      "get" ->
        linkdefs = get_link_definitions()
        {:reply, Msgpax.pack!(linkdefs)}

      "del" ->
        ld = Msgpax.unpack!(body)
        key = {ld["actor_id"], ld["contract_id"], ld["link_name"]}
        :ets.delete(:linkdef_table, key)

      _ ->
        {:error, "Unsupported linkdef command (#{cmd})"}
    end
  end

  def get_link_definitions() do
    :ets.tab2list(:linkdef_table)
    |> Enum.map(fn {{pk, contract, link}, %{provider_key: provider_key, values: values}} ->
      %{
        actor_id: pk,
        provider_id: provider_key,
        link_name: link,
        contract_id: contract,
        values: values
      }
    end)
  end
end
