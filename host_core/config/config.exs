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

config :opentelemetry, :resource, service: %{name: "wasmcloud"}

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none

# Subscription retention is a test-enabling tool. When enabled, a subscriber for
# an actor _will not unsubscribe_ after all instances of that actor have been
# removed from a host. This helps in testing because the constant churning of
# stopping, unsubscribing, starting, and re-subscribing in the middle of a test
# suite causes failure and race conditions on a large scale.
#
# tl;dr - leave subscription retention off at all times unless you're running
# tests.
config :host_core,
  retain_rpc_subscriptions: false

import_config "#{config_env()}.exs"
