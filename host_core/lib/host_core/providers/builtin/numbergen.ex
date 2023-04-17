defmodule HostCore.Providers.Builtin.Numbergen do
  @moduledoc """
  A provider that generates random numbers and GUIDs.
  """

  def invoke("NumberGen.GenerateGuid", _payload) do
    UUID.uuid4()
    |> Msgpax.pack!()
    |> IO.iodata_to_binary()
  end

  def invoke("NumberGen.RandomInRange", payload) do
    params = Msgpax.unpack!(payload)

    min = max(params["min"], 0)
    max = min(params["max"], 4_294_967_295)

    Enum.random(min..max)
    |> Msgpax.pack!()
    |> IO.iodata_to_binary()
  end

  def invoke("NumberGen.Random32", _payload) do
    Enum.random(0..4_294_967_295)
    |> Msgpax.pack!()
    |> IO.iodata_to_binary()
  end

  def invoke("NumberGen.RandomBytes", payload) do
    bytes = Msgpax.unpack!(payload)

    for(_ <- 1..bytes, do: Enum.random(0..255))
    |> Msgpax.pack!()
    |> IO.iodata_to_binary()
  end
end
