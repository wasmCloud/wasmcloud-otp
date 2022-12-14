defmodule HostCore.MetadataCache do
  @moduledoc """
  One metadata cache exists per lattice. This genserver is started by a lattice supervisor and is responsible for synchronizing
  the in-memory caches managed by `HostCore.Linkdefs.Manager`, `HostCore.Refmaps.Manager`, `HostCore.Claims.Manager` with the
  underlying NATS key-value bucket
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    {:ok,
     %{
       lattice_prefix: opts[:lattice_prefix],
       js_domain: opts[:js_domain]
     }}
  end
end
