defmodule HostCore.Refmaps.Manager do
  @moduledoc false
  require Logger

  alias HostCore.CloudEvent

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

  def ocis_for_key(public_key) when is_binary(public_key) do
    :ets.tab2list(:refmap_table)
    |> Enum.filter(fn {_ociref, pk} -> pk == public_key end)
    |> Enum.map(fn {ociref, _pk} -> ociref end)
  end

  def publish_refmap(oci_url, public_key) do
    Logger.debug("Publishing ref map")
    prefix = HostCore.Host.lattice_prefix()
    topic = "lc.#{prefix}.ocimap.#{HostCore.Nats.sanitize_for_topic(oci_url)}"
    event_topic = "wasmbus.evt.#{prefix}"

    evtmsg =
      %{
        oci_url: oci_url,
        public_key: public_key
      }
      |> CloudEvent.new("ocimap_set")

    Gnat.pub(:control_nats, topic, Jason.encode!(%{oci_url: oci_url, public_key: public_key}))
    Gnat.pub(:control_nats, event_topic, evtmsg)
  end
end
