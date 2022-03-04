defmodule HostCore.MixProject do
  use Mix.Project

  @app_vsn "0.52.4"

  def project do
    [
      app: :host_core,
      version: @app_vsn,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      rustler_crates: [
        hostcore_wasmcloud_native: [
          mode: if(Mix.env() == :dev, do: :debug, else: :release)
        ]
      ],
      dialyzer: [plt_add_deps: :apps_direct]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {HostCore, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:wasmex, "~> 0.5.0"},
      {:msgpax, "~> 2.3"},
      {:rustler, "~> 0.22.0"},
      {:jason, "~> 1.2.2"},
      {:gnat, "~> 1.2"},
      {:cloudevents, "~> 0.4.0"},
      {:uuid, "~> 1.1"},

      # {:vapor, "~> 0.10.0"},
      # TODO: switch to new version of vapor once PR is merged
      {:vapor, git: "https://github.com/autodidaddict/vapor"},
      {:hashids, "~> 2.0"},
      {:parallel_task, "~> 0.1.1"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:httpoison, "~> 1.8", only: [:test]},
      {:json, "~> 1.4", only: [:test]},
      {:distillery, "~> 2.0"}
    ]
  end
end
