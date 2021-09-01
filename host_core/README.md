# wasmCloud Host Core
This is the Elixir OTP core or _functional engine_ of the server process.

The use of the [Makefile](./Makefile) is preferred for building and running this project due to its NIF dependencies. Use the respective `make build` and `make run` options to build and run `host_core`.

## Installation and Running

If you have a functioning Elixir development environment that includes NATS, then you can simply git pull this entire repository, `cd` into the `host_core` directory, and run `iex -S mix` to launch the application with an active `iex` console.

If instead you prefer to work from the production release, then consult our [installation](https://wasmcloud.dev/overview/installation/) guide for the exact instructions.

### NATS

This OTP application requires the use of NATS with the JetStream server enabled (**v2.3.4** or later). Thankfully JetStream comes built-in to all NATS servers and you can simply launch your server with the `-js` or `--jetstream` flag. 

This OTP application will _fail to start_ without a running NATS server.

For information on how to configure the OTP application (which includes supplying NATS connection information), check out the [host runtime](https://wasmcloud.dev/reference/host-runtime/) reference.
