defmodule HostCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :host_core,
      version: "0.20.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      #   compilers: [:rustler] ++ Mix.compilers(),
      rustler_crates: [
        hostcore_wasmcloud_native: [
          mode: if(Mix.env() == :prod, do: :release, else: :debug)
        ]
      ],
      deps: deps(),
      dialyzer: [plt_add_deps: :apps_direct]
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
      {:wasmex, "~> 0.4.0"},
      {:msgpax, "~> 2.3"},
      {:rustler, "~> 0.22.0"},
      {:gnat, "~> 1.2"},
      {:cloudevents, "~> 0.4.0"},
      {:uuid, "~> 1.1"},
      {:jason, "~> 1.2.2"},
      {:vapor, "~> 0.10.0"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:httpoison, "~> 1.8", only: [:test]},
      {:json, "~> 1.4", only: [:test]}
    ]
  end
end
