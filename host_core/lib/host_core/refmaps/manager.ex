defmodule HostCore.Refmaps.Manager do
  use GenServer, restart: :transient
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :refmaps_manager)
  end

  @impl true
  def init(_opts) do
    {:ok, :ok}
  end

  def lookup_refmap(oci_url) do
    case :ets.lookup(:refmap_table, oci_url) do
      [pk] -> {:ok, pk}
      [] -> :error
    end
  end

  def cache_refmap(oci_url, public_key) do
    :ets.insert(:refmap_table, {oci_url, public_key})
  end

  def put_refmap(oci_url, public_key) do
    cache_refmap(oci_url, public_key)

    publish_refmap(oci_url, public_key)
  end

  def publish_refmap(oci_url, public_key) do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.refmaps.put"

    Gnat.pub(:lattice_nats, topic, Msgpax.pack!(%{oci_url: oci_url, public_key: public_key}))
  end

  def request_refmaps() do
    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.rpc.#{prefix}.refmaps.get"

    case Gnat.request(:lattice_nats, topic, [], receive_timeout: 2_000) do
      {:ok, %{body: body}} ->
        # Unpack refmaps, convert to map with atom keys
        Msgpax.unpack!(body)
        |> Enum.map(fn refmaps ->
          refmaps
          |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
        end)

      {:error, :timeout} ->
        Logger.debug("No response for refmaps get, starting with empty refmaps cache")
        []

      _ ->
        []
    end
  end
end
