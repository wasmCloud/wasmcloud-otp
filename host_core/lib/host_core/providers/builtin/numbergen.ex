defmodule HostCore.Providers.Builtin.Numbergen do
  def invoke("GenerateGuid", _payload) do
    Msgpax.pack!(UUID.uuid4())
  end

  def invoke("RandomInRange", payload) do
    params = Msgpax.unpack!(payload)

    min = min(params["min"], 0)
    max = max(params["max"], 4_294_967_295)
    Msgpax.pack!(Enum.random(min..max))
  end

  def invoke("Random32", _payload) do
    Msgpax.pack!(floor(:rand.uniform(4_294_967_294)))
  end
end
