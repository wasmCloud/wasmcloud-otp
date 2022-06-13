defmodule HostCore.MixProject do
  use Mix.Project

  @app_vsn "0.54.6"

  def project do
    [
      app: :host_core,
      version: @app_vsn,
      elixir: "~> 1.13",
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

  # In order to ensure that TLS cert check starts before the otel applications,
  # we disable auto-start from dependencies and start them in explicit order in the
  # application function
  def application do
    [
      extra_applications: [
        :logger,
        :crypto,
        :tls_certificate_check,
        :opentelemetry_exporter,
        :opentelemetry
      ],
      mod: {HostCore, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:wasmex, "~> 0.7.0"},
      {:msgpax, "~> 2.3"},
      {:rustler, "~> 0.24.0"},
      {:timex, "~> 3.7"},
      {:jason, "~> 1.2.2"},
      {:gnat, "~> 1.5.2"},
      # erlavro isn't used, but this version upgrades dependency of cloudevents 0.4.0 to use rebar3
      {:erlavro, "~> 2.9.7", override: true, manager: :rebar3},
      {:cloudevents, "~> 0.4.0"},
      {:uuid, "~> 1.1"},
      {:opentelemetry_api, "~> 1.0"},
      {:opentelemetry, "~> 1.0", application: false},
      {:opentelemetry_exporter, "~> 1.0", application: false},
      {:opentelemetry_logger_metadata, "~> 0.1.0"},

      # {:vapor, "~> 0.10.0"},
      # TODO: switch to new version of vapor once PR is merged
      {:vapor, git: "https://github.com/autodidaddict/vapor"},
      {:hashids, "~> 2.0"},
      {:parallel_task, "~> 0.1.1"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:httpoison, "~> 1.8", only: [:test]},
      {:json, "~> 1.4", only: [:test]},
      {:distillery, "~> 2.1"}
    ]
  end
end
