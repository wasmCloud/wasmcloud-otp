![wasmCloud logo](https://raw.githubusercontent.com/wasmCloud/branding/main/02.Horizontal%20Version/Pixel/PNG/Wasmcloud.Logo-Hrztl_Color.png)

[![wasmcloud_host build status](https://img.shields.io/github/actions/workflow/status/wasmcloud/wasmcloud-otp/wasmcloud_host.yml?branch=main)](https://github.com/wasmCloud/wasmcloud-otp/actions/workflows/wasmcloud_host.yml)
[![latest release](https://img.shields.io/github/v/release/wasmcloud/wasmcloud-otp?include_prereleases)](https://github.com/wasmCloud/wasmcloud-otp/releases)
[![homepage](https://img.shields.io/website?label=homepage&url=https%3A%2F%2Fwasmcloud.com)](https://wasmcloud.com)
[![documentation site](https://img.shields.io/website?label=documentation&url=https%3A%2F%2Fwasmcloud.dev)](https://wasmcloud.dev)
![Powered by WebAssembly](https://img.shields.io/badge/powered%20by-WebAssembly-orange.svg)

# wasmCloud Host Runtime (OTP)

The wasmCloud Host Runtime is a server process that securely hosts and provides dispatch for [actors](https://wasmcloud.dev/reference/host-runtime/actors/) and [capability providers](https://wasmcloud.dev/reference/host-runtime/capabilities/).

This runtime is designed to take advantage of WebAssembly's small footprint, secure sandbox, speed, and portability to allow developers to write boilerplate-free code that embraces the [actor model](https://en.wikipedia.org/wiki/Actor_model) and abstracts away dependencies on [non-functional requirements](https://www.scaledagileframework.com/nonfunctional-requirements/) via well-defined [interfaces](https://github.com/wasmCloud/interfaces/).

This host runtime is written in [Elixir][elixir] and extensively leverages the decades of work, testing, and improvements that have gone into the **OTP** framework.
There are a number of excellent Elixir and OTP references online, but we highly recommend starting with the [Pragmatic Programmers](https://pragprog.com/categories/elixir-phoenix-and-otp/) Elixir and OTP library of books.

## Getting started

To install and explore wasmCloud (and this host runtime), check out the [documentation for getting started](https://wasmcloud.dev/overview/getting-started/).

## Architecture

The wasmCloud Host Runtime is made up of two pieces:

- The Host Core
- Dashboard Web UI

### Host Core

The **host core** consists of all of the "headless" (no UI) functional components of the system. This OTP application and its contained supervision tree represent the _core_ of the wasmCloud OTP host runtime.

You can find the [host core](./host_core/README.md) in this github repository.

### Dashboard Web UI

The dashboard web UI (often colloquially referred to as the _washboard_) is a **Phoenix** application that fits snugly atop the host core, providing real-time web access to a variety of information, telemetry, and insight while also exposing a graphical interface to controlling the host and portions of the lattice.

You can find the [dashboard UI](./wasmcloud_host/README.md) in this github repository.

## Dependencies

### NATS

All of wasmCloud's _lattice_ functionality requires the use of [NATS](https://nats.io). To learn more, check out the [lattice](https://wasmcloud.dev/reference/lattice/) section of our documentation.

## Development

### Pre-requisites

- (optional) [`asdf`][asdf] with [`asdf-elixir`][asdf-elixir] for managing versions of your [`elixir`][elixir] toolchain (see `.tool-versions`)

**NOTE** If you manage your Elixir toolchain manually, please make sure to use a version that matches the contents of `.tool-versions`.

[asdf]: https://asdf-vm.com/
[asdf-elixir]: https://github.com/asdf-vm/asdf-elixir
[elixir]: https://elixir-lang.org/
