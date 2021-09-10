defmodule HostCore.Providers.Builtin.Numbergen do
  @moduledoc false

  def invoke(method, _payload)
      when method in ["NumberGen.GenerateGuid", "GenerateGuid"] do
    IO.iodata_to_binary(Msgpax.pack!(UUID.uuid4()))
  end

  def invoke(method, payload)
      when method in ["NumberGen.RandomInRange", "RandomInRange"] do
    params = Msgpax.unpack!(payload)

    min = max(params["min"], 0)
    max = min(params["max"], 4_294_967_295)
    IO.iodata_to_binary(Msgpax.pack!(Enum.random(min..max)))
  end

  def invoke(method, _payload)
      when method in ["NumberGen.Random32", "Random32"] do
    IO.iodata_to_binary(Msgpax.pack!(Enum.random(0..4_294_967_295)))
  end
end
