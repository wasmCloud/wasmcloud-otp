![wasmCloud logo](https://raw.githubusercontent.com/wasmCloud/branding/main/02.Horizontal%20Version/Pixel/PNG/Wasmcloud.Logo-Hrztl_Color.png)
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2FwasmCloud%2Fwasmcloud-otp.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2FwasmCloud%2Fwasmcloud-otp?ref=badge_shield)

[![wasmcloud_host build status](https://img.shields.io/github/workflow/status/wasmcloud/wasmcloud-otp/WasmcloudHost%20Elixir%20CI)](https://github.com/wasmCloud/wasmcloud-otp/actions/workflows/wasmcloud_host.yml)
[![latest release](https://img.shields.io/github/v/release/wasmcloud/wasmcloud-otp?include_prereleases)](https://github.com/wasmCloud/wasmcloud-otp/releases)
[![homepage](https://img.shields.io/website?label=homepage&url=https%3A%2F%2Fwasmcloud.com)](https://wasmcloud.com)
[![documentation site](https://img.shields.io/website?label=documentation&url=https%3A%2F%2Fwasmcloud.dev)](https://wasmcloud.dev)

# wasmCloud Host Runtime (OTP)

The wasmCloud Host Runtime is a server process that securely hosts and provides dispatch for [actors](https://wasmcloud.dev/reference/host-runtime/actors/) and [capability providers](https://wasmcloud.dev/reference/host-runtime/capabilities/). This runtime is designed to take advantage of WebAssembly's small footprint, secure sandbox, speed, and portability to allow developers to write boilerplate-free code that embraces the [actor model](https://en.wikipedia.org/wiki/Actor_model) and abstracts away dependencies on [non-functional requirements](https://www.scaledagileframework.com/nonfunctional-requirements/) via well-defined [interfaces](https://github.com/wasmCloud/interfaces/).

This host runtime is written in Elixir and extensively leverages the decades of work, testing, and improvements that have gone into the **OTP** framework. There are a number of excellent Elixir and OTP references online, but we highly recommend starting with the [Pragmatic Programmers](https://pragprog.com/categories/elixir-phoenix-and-otp/) Elixir and OTP library of books.

To get started with installation and exploration, check out the [getting started](https://wasmcloud.dev/overview/getting-started/) section of our documentation.

The wasmCloud Host Runtime is made up of two pieces:

- The Host Core
- Dashboard Web UI

## Host Core

The **host core** consists of all of the "headless" (no UI) functional components of the system. This OTP application and its contained supervision tree represent the _core_ of the wasmCloud OTP host runtime.

You can find the [host core](./host_core/README.md) in this github repository.

## Dashboard Web UI

The dashboard web UI (often colloquially referred to as the _washboard_) is a **Phoenix** application that fits snugly atop the host core, providing real-time web access to a variety of information, telemetry, and insight while also exposing a graphical interface to controlling the host and portions of the lattice.

You can find the [dashboard UI](./wasmcloud_host/README.md) in this github repository.

### NATS

All of wasmCloud's _lattice_ functionality requires the use of [NATS](https://nats.io). To learn more, check out the [lattice](https://wasmcloud.dev/reference/lattice/) section of our documentation.


## License
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2FwasmCloud%2Fwasmcloud-otp.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2FwasmCloud%2Fwasmcloud-otp?ref=badge_large)