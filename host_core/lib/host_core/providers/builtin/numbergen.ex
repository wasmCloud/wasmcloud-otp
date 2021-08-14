defmodule HostCore.Providers.Builtin.Numbergen do
  def invoke("GenerateGuid", _payload) do
    Msgpax.pack!(UUID.uuid4())
  end

  def invoke("RandomInRange", payload) do
    params = Msgpax.unpack!(payload)

    min = max(params["min"], 0)
    max = min(params["max"] - 1, 4_294_967_295)
    Msgpax.pack!(Enum.random(min..max))
  end

  def invoke("Random32", _payload) do
    Msgpax.pack!(Enum.random(0..4_294_967_295))
  end
end
