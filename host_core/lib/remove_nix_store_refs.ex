defmodule HostCore.RemoveNixStoreRefs do
  alias Burrito.Builder.Step
  @behaviour Step

  @impl Step
  def execute(%Burrito.Builder.Context{} = context) do
    store = Regex.compile!("/nix/store/[[:alnum:]-.]+")

    elixir =
      Path.join(context.work_dir, [
        "releases",
        "/#{context.mix_release.version}",
        "/elixir"
      ])

    File.write!(elixir, String.replace(File.read!(elixir), store, ""))

    iex =
      Path.join(context.work_dir, [
        "releases",
        "/#{context.mix_release.version}",
        "/iex"
      ])

    File.write!(iex, String.replace(File.read!(iex), store, ""))

    context
  end
end
