defmodule HostCore.Providers.Builtin.Numbergen do
  def invoke(method, _payload)
      when method == "NumberGen.GenerateGuid" or method == "GenerateGuid" do
    IO.iodata_to_binary(Msgpax.pack!(UUID.uuid4()))
  end

  def invoke(method, payload)
      when method == "NumberGen.RandomInRange" or method == "RandomInRange" do
    params = Msgpax.unpack!(payload)

    min = max(params["min"], 0)
    max = min(params["max"], 4_294_967_295)
    IO.iodata_to_binary(Msgpax.pack!(Enum.random(min..max)))
  end

  def invoke(method, _payload)
      when method == "NumberGen.Random32" or method == "RandomRandom32" do
    IO.iodata_to_binary(Msgpax.pack!(Enum.random(0..4_294_967_295)))
  end
end
