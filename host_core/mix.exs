defmodule HostCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :host_core,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      compilers: [:rustler] ++ Mix.compilers(),
      rustler_crates: [
        hostcore_wasmcloud_native: [
          mode: if(Mix.env() == :prod, do: :release, else: :debug)
        ],
      ],
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {HostCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:wasmex, "~> 0.3.1"},
      {:msgpax, "~> 2.3"},
      {:rustler, "~> 0.21.1"},
      {:gnat, "~> 1.2"},
      {:cloudevents, "~> 0.4.0"},
      {:uuid, "~> 1.1"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false}
      # {:grpc, "~> 0.5.0-beta.1"}
      # { :benchwarmer, "~> 0.0.2" }
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  # Setup dialyzer
  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end
end
