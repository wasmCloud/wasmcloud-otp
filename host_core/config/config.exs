# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#

config :rustler_precompiled, :force_build, wasmex: true

config :logger, :console,
  format: {HostCore.ConsoleLogger, :format},
  level: :info,
  metadata: :all,
  device: :standard_error

config :opentelemetry, :resource, service: %{name: "wasmcloud"}

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none

import_config "#{config_env()}.exs"
