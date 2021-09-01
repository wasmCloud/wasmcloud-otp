# wasmCloud Host Runtime (OTP)
The wasmCloud Host Runtime is a server process that securely hosts and provides dispatch for [actors](https://wasmcloud.dev/reference/host-runtime/actors/) and [capability providers](https://wasmcloud.dev/reference/host-runtime/capabilities/). This runtime is designed to take advantage of WebAssembly's small footprint, secure sandbox, speed, and portability to allow developers to write boilerplate-free code that embraces the [actor model](https://en.wikipedia.org/wiki/Actor_model) and abstracts away dependencies on [non-functional requirements](https://www.scaledagileframework.com/nonfunctional-requirements/) via well-defined [interfaces](https://github.com/wasmCloud/interfaces/).

This host runtime is written in Elixir and extensively leverages the decades of work, testing, and improvements that have gone into the **OTP** framework. There are a number of excellent Elixir and OTP references online, but we highly recommend starting with the [Pragmatic Programmers](https://pragprog.com/categories/elixir-phoenix-and-otp/) Elixir and OTP library of books.

To get started with installation and exploration, check out the [getting started](https://wasmcloud.dev/overview/getting-started/) section of our documentation.

The wasmCloud Host Runtime is made up of two pieces:

* The Host Core
* Dashboard Web UI

## Host Core
The **host core** consists of all of the "headless" (no UI) functional components of the system. This OTP application and its contained supervision tree represent the _core_ of the wasmCloud OTP host runtime.

You can find the [host core](./host_core/README.md) in this github repository.

## Dashboard Web UI
The dashboard web UI (often colloquially referred to as the _washboard_) is a **Phoenix** application that fits snugly atop the host core, providing real-time web access to a variety of information, telemetry, and insight while also exposing a graphical interface to controlling the host and portions of the lattice.

You can find the [dashboard UI](./wasmcloud_host/README.md) in this github repository.

### NATS
All of wasmCloud's _lattice_ functionality requires the use of [NATS](https://nats.io).