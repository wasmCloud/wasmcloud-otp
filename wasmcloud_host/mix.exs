defmodule WasmcloudHost.MixProject do
  use Mix.Project

  @app_vsn "0.63.2"

  def project do
    [
      app: :wasmcloud_host,
      version: @app_vsn,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      releases: [
        wasmcloud_host:
          if Mix.env() == :prod do
            [
              steps: [:assemble, &Burrito.wrap/1],
              burrito: [
                targets: [
                  aarch64_darwin: [
                    os: :darwin,
                    cpu: :aarch64,
                    custom_erts: System.get_env("ERTS_AARCH64_DARWIN")
                  ],
                  aarch64_linux_gnu: [
                    os: :linux,
                    cpu: :aarch64,
                    libc: :gnu,
                    custom_erts: System.get_env("ERTS_AARCH64_LINUX_GNU")
                  ],
                  aarch64_linux_musl: [
                    os: :linux,
                    cpu: :aarch64,
                    libc: :musl,
                    custom_erts: System.get_env("ERTS_AARCH64_LINUX_MUSL")
                  ],
                  x86_64_darwin: [
                    os: :darwin,
                    cpu: :x86_64,
                    custom_erts: System.get_env("ERTS_X86_64_DARWIN")
                  ],
                  x86_64_linux_gnu: [
                    os: :linux,
                    cpu: :x86_64,
                    libc: :gnu,
                    custom_erts: System.get_env("ERTS_X86_64_LINUX_GNU")
                  ],
                  x86_64_linux_musl: [
                    os: :linux,
                    cpu: :x86_64,
                    libc: :musl,
                    custom_erts: System.get_env("ERTS_X86_64_LINUX_MUSL")
                  ],
                  x86_64_windows: [
                    os: :windows,
                    cpu: :x86_64,
                    custom_erts: System.get_env("ERTS_X86_64_WINDOWS")
                  ]
                ],
                extra_steps: [
                  patch: [
                    pre: [HostCore.CopyNIF],
                    post: [HostCore.RemoveNixStoreRefs]
                  ]
                ]
              ]
            ]
          else
            []
          end
      ],
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {WasmcloudHost.Application, []},
      extra_applications: [:logger, :runtime_tools, :host_core],
      env: [app_version: @app_vsn]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.6.0"},
      {:phoenix_html, "~> 3.0.4"},
      {:phoenix_live_view, "~> 0.16.4"},
      {:phoenix_live_dashboard, "~> 0.5"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:esbuild, "~> 0.2"},
      {:dart_sass, "~> 0.5", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 0.5"},
      {:floki, ">= 0.30.0", only: :test},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.0"},
      {:host_core, path: "../host_core"},
      {:file_system, "~> 0.2"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:burrito, github: "burrito-elixir/burrito"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "assets.deploy": ["esbuild default --minify", "phx.digest"]
    ]
  end
end
