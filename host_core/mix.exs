defmodule HostCore.MixProject do
  use Mix.Project

  @app_vsn "0.62.0"

  def project do
    [
      app: :host_core,
      version: @app_vsn,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      rustler_crates: [
        hostcore_wasmcloud_native: [
          mode: if(Mix.env() == :dev, do: :debug, else: :release)
        ]
      ],
      releases: [
        host_core: [
          steps: conditional_steps()
        ]
      ],
      dialyzer: [plt_add_deps: :apps_direct]
    ]
  end

  # TODO https://github.com/wasmCloud/wasmcloud-otp/issues/570
  defp conditional_steps do
    case :os.type() do
      {:unix, _} -> [:assemble, &Bakeware.assemble/1]
      _ -> [:assemble]
    end
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
      mod: {HostCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    list = [
      {:msgpax, "~> 2.3"},
      {:rustler, "~> 0.27.0"},
      {:timex, "~> 3.7"},
      {:jason, "~> 1.4.0"},
      {:gnat, "~> 1.6.0"},
      {:cloudevents, "~> 0.6.1"},
      {:uuid, "~> 1.1"},
      {:opentelemetry_api, "~> 1.2"},
      {:opentelemetry, "~> 1.2.1", application: false},
      {:opentelemetry_exporter, "~> 1.3", application: false},
      {:opentelemetry_logger_metadata, "~> 0.1.0"},
      {:phoenix_pubsub, "~> 2.1.1"},

      # {:vapor, "~> 0.10.0"},
      # TODO: switch to new version of vapor once PR is merged
      {:vapor, git: "https://github.com/autodidaddict/vapor"},
      {:hashids, "~> 2.0"},
      {:parallel_task, "~> 0.1.1"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:httpoison, "~> 1.8", only: [:test]},
      {:json, "~> 1.4", only: [:test]},
      {:yaml_elixir, "~> 2.9.0"},
      {:toml, "~> 0.7"},
      {:benchee, "~> 1.0", only: :test},
      {:mock, "~> 0.3.0", only: :test}
    ]

    # TODO https://github.com/wasmCloud/wasmcloud-otp/issues/570
    case :os.type() do
      {:unix, _} -> [{:bakeware, "~> 0.2.4"} | list]
      _ -> list
    end
  end
end
