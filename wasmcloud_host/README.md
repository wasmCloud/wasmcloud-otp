[![wasmcloud_host build status](https://img.shields.io/github/workflow/status/wasmcloud/wasmcloud-otp/WasmcloudHost%20Elixir%20CI)](https://github.com/wasmCloud/wasmcloud-otp/actions/workflows/wasmcloud_host.yml)

# wasmCloud Host - Web UI Dashboard

This is the web UI dashboard that provides for a basic way to interact with a host and its associated lattice. This web application automatically starts the [host_core](../host_core/README.md) application as a dependency.

## Prerequisites

- [Elixir installation](https://elixir-lang.org/install.html), minimum `v1.12.0`
- [Erlang/OTP installation](https://elixir-lang.org/install.html#installing-erlang), minimum `OTP 22`
- [NATS installation](https://docs.nats.io/nats-server/installation), minimum `v2.7.2`

## Starting the Host and Web UI Dashboard

To start the wasmCloud host and web ui, cd to this folder (wasmcloud_host), and type or paste these commands:

```
# start NATS in the background
nats-server -js &

# install dependencies
mix deps.get
make esbuild

# start the host
mix phx.server
```

Alternatively, you can simply start NATS as shown above and run `make run` to perform the above steps and run the dashboard.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser. If you want to use a different HTTP port for the dashboard, set the environment variable PORT, for example,

`PORT=8000 mix phx.server`

If you later update the source from github, you'll need to re-run the set of commands above.

To learn more about wasmCloud, please view the [Documentation](https://wasmcloud.dev).
