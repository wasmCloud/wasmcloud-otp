defmodule HostCore.Refmaps.Manager do
  @moduledoc """
  The reference maps manager is responsible for managing the association of public keys with the repository address references
  which can be OCI refereences or bindle references. You can look up a reference by its OCI/bindle URL as well as obtain a list
  of reference maps for a given public key. When multiple versions of the same wasm module have been published to the same lattice,
  that lattice reference maps cache can contain multiple reference URLs for a single key
  """
  require Logger

  import HostCore.Jetstream.MetadataCacheLoader, only: [broadcast_event: 3]

  alias HostCore.CloudEvent
  alias HostCore.Jetstream.Client, as: JetstreamClient
  alias HostCore.Vhost.VirtualHost

  def lookup_refmap(lattice_prefix, oci_url) do
    rt = table_atom(lattice_prefix)

    case :ets.lookup(rt, oci_url) do
      [pk] -> {:ok, pk}
      [] -> :error
    end
  end

  def cache_refmap(lattice_prefix, oci_url, public_key) do
    rt = table_atom(lattice_prefix)
    :ets.insert(rt, {oci_url, public_key})
  end

  def put_refmap(host_id, lattice_prefix, oci_url, public_key) do
    cache_refmap(lattice_prefix, oci_url, public_key)

    publish_refmap(host_id, lattice_prefix, oci_url, public_key)
  end

  def ocis_for_key(lattice_prefix, public_key) when is_binary(public_key) do
    rt = table_atom(lattice_prefix)

    :ets.tab2list(rt)
    |> Enum.filter(fn {_ociref, pk} -> pk == public_key end)
    |> Enum.map(fn {ociref, _pk} -> ociref end)
  end

  def publish_refmap(host_id, lattice_prefix, oci_url, public_key) do
    config = VirtualHost.config(host_id)

    data = %{
      oci_url: oci_url,
      public_key: public_key
    }

    Logger.debug("Publishing OCI ref map for #{inspect(oci_url)}")

    JetstreamClient.kv_put(
      lattice_prefix,
      config.js_domain,
      "REFMAP_#{HostCore.Nats.sanitize_for_topic(oci_url)}",
      Jason.encode!(data)
    )

    broadcast_event(:refmap_added, data, lattice_prefix)

    data
    |> CloudEvent.new("refmap_set", host_id)
    |> CloudEvent.publish(lattice_prefix)
  end

  def table_atom(prefix) when is_binary(prefix) do
    String.to_atom("refmap_#{prefix}")
  end
end
