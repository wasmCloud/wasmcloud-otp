defmodule HostCore.ClaimsManager do
  use GenServer, restart: :transient

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :claims_manager)
  end

  @impl true
  def init(opts) do
    # subscribe to all claims put / get ops
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.claims.*"
    {:ok, _sub} = Gnat.sub(:lattice_nats, self(), topic)

    {:ok, :ok}
  end

  @impl true
  def handle_info(
        {:msg, %{body: body, topic: topic}},
        state
      ) do
    cmd = topic |> String.split(".") |> Enum.at(4)
    Logger.info("Received claims command (#{cmd})")
    claims = Msgpax.unpack!(body) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    key = claims.public_key
    :ets.insert(:claims_table, {key, claims})

    {:noreply, state}
  end

  def put_claims(claims) do
    key = claims.public_key

    claims = %{
      call_alias: claims.call_alias,
      issuer: claims.issuer,
      name: claims.name,
      revision: claims.revision,
      tags: claims.tags,
      version: claims.version,
      public_key: claims.public_key
    }

    :ets.insert(:claims_table, {key, claims})
    publish_claims(claims)
  end

  def lookup_claims(public_key) do
    case :ets.lookup(:claims_table, public_key) do
      [ld] -> {:ok, ld}
      [] -> :error
    end
  end

  defp publish_claims(claims) do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.claims.put"

    Gnat.pub(:lattice_nats, topic, Msgpax.pack!(claims))
  end
end
