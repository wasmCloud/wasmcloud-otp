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

    :ets.insert(:claims_table, {key, claims})
    publish_claims(claims)
  end

  def request_claims() do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.claims.get"

    case Gnat.request(:lattice_nats, topic, [], receive_timeout: 2_000) do
      {:ok, %{body: body}} ->
        # Insert values into claims table with key being the subject key
        Msgpax.unpack!(body)
        |> Enum.map(fn claims -> Map.get(claims, "values") end)
        # Convert string keys to atoms
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
