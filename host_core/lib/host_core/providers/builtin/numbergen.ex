defmodule HostCore.Providers.Builtin.Numbergen do
  def invoke("NumberGen.GenerateGuid", _payload, _api_version) do
    IO.iodata_to_binary(Msgpax.pack!(UUID.uuid4()))
  end

  def invoke("NumberGen.RandomInRange", payload, _api_version) do
    params = Msgpax.unpack!(payload)

    min = max(params["min"], 0)
    max = min(params["max"], 4_294_967_295)
    IO.iodata_to_binary(Msgpax.pack!(Enum.random(min..max)))
  end

  def invoke("NumberGen.Random32", _payload, _api_version) do
    IO.iodata_to_binary(Msgpax.pack!(Enum.random(0..4_294_967_295)))
  end
end
