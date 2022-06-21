defmodule HostCore.Actors.CallCounter do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    :ets.new(__MODULE__, [:public, :set, :named_table])

    {:ok, nil}
  end

  def read_and_increment(pk) when is_binary(pk) do
    :ets.update_counter(HostCore.Actors.CallCounter, pk, 1, {pk, -1})
  end
end
