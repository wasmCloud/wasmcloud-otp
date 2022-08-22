defmodule HostCore.MixProject do
  use Mix.Project

  @app_vsn "0.56.0"

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
      # 🌯
      releases: [
        host_core: [
          steps: [:assemble, &Burrito.wrap/1],
          burrito: [
            targets: [
              # Officially supported
              macos: [os: :darwin, cpu: :x86_64],
              linux: [os: :linux, cpu: :x86_64],
              linux_musl: [os: :linux_musl, cpu: :x86_64],
              windows: [os: :windows, cpu: :x86_64],
              # Needs custom erts
              macos_m1: [os: :darwin, cpu: :arm64],
              linux_arm64: [os: :linux, cpu: :arm64],
              linux_musl_arm64: [os: :linux_musl, cpu: :arm64]
            ]
          ]
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
      {:cloudevents, "~> 0.6.1"},
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
      {:benchee, "~> 1.0", only: :test},
      {:mock, "~> 0.3.0", only: :test},
      {:burrito, github: "burrito-elixir/burrito"},
      # TODO: just contribute 0.3.0 to burrito
      {:typed_struct, "~> 0.3.0", override: true},
      {:distillery, "~> 2.1"}
    ]
  end
end
