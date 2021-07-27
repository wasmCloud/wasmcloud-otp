defmodule HostCore.Claims.Manager do
  use GenServer, restart: :transient

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :claims_manager)
  end

  @impl true
  def init(_opts) do
    {:ok, :ok}
  end

  def lookup_claims(public_key) do
    case :ets.lookup(:claims_table, public_key) do
      [c] -> {:ok, c}
      [] -> :error
    end
  end

  def cache_claims(key, claims) do
    :ets.insert(:claims_table, {key, claims})
  end

  def cache_call_alias(call_alias, public_key) do
    if call_alias != nil && String.length(call_alias) > 1 do
      :ets.insert_new(:callalias_table, {call_alias, public_key})
    end
  end

  def put_claims(claims) do
    key = claims.public_key

    claims = %{
      call_alias:
        if claims.call_alias == nil do
          ""
        else
          claims.call_alias
        end,
      iss: claims.issuer,
      name: claims.name,
      caps:
        if claims.caps == nil do
          ""
        else
          Enum.join(claims.caps, ",")
        end,
      rev:
        if claims.revision == nil do
          "0"
        else
          Integer.to_string(claims.revision)
        end,
      tags:
        if claims.tags == nil do
          ""
        else
          Enum.join(claims.tags, ",")
        end,
      version: claims.version,
      sub: claims.public_key
    }

    cache_claims(key, claims)
    publish_claims(claims)
  end

  defp publish_claims(claims) do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.claims.put"

    Gnat.pub(:lattice_nats, topic, Msgpax.pack!(claims))
  end

  def request_claims() do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.claims.get"

    case Gnat.request(:lattice_nats, topic, [], receive_timeout: 2_000) do
      {:ok, %{body: body}} ->
        # Unpack claims, convert to map with atom keys
        Msgpax.unpack!(body)
        |> Enum.map(fn claims ->
          claims
          |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
        end)

      {:error, :timeout} ->
        Logger.debug("No response for claims get, starting with empty claims cache")
        []

      _ ->
        []
    end
  end
end
