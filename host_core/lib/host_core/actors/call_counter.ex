defmodule HostCore.Actors.CallCounter do
  @moduledoc """
  Simple incrementing counter process. The only real difference between this process and
  a standard counter is that this one has a specific key that corresponds to an actor's public
  key and the lattice where that actor is running.
  """
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    :ets.new(__MODULE__, [:public, :set, :named_table])

    {:ok, nil}
  end

  def read_and_increment(pk, lattice_prefix) when is_binary(pk) and is_binary(lattice_prefix) do
    key = key(pk, lattice_prefix)
    :ets.update_counter(__MODULE__, key, 1, {key, -1})
  end

  defp key(pk, lattice_prefix) do
    "#{pk}-#{lattice_prefix}"
  end
end
