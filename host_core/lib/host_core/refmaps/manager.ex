defmodule HostCore.Refmaps.Manager do
  @moduledoc false
  require Logger

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
    Logger.debug("Publishing ref map")
    prefix = HostCore.Host.lattice_prefix()
    topic = "lc.#{prefix}.ocimap.#{HostCore.Nats.sanitize_for_topic(oci_url)}"

    Gnat.pub(:control_nats, topic, Jason.encode!(%{oci_url: oci_url, public_key: public_key}))
  end
end
