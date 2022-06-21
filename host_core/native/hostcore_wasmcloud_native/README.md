# NIF for Elixir.HostCore.WasmCloud.Native
This Native Implemented Function ([NIF](https://www.erlang.org/doc/tutorial/nif.html)) serves two purposes for wasmCloud:
1. Implement functionality that is better suited for the memory safety or static typing of Rust
2. Reuse common functionality in the various crates published in the Rust ecosystem.

## To build the NIF module:

- Make sure your projects `mix.exs` has the `:rustler` compiler listed in the `project` function: `compilers: [:rustler] ++ Mix.compilers()` If there already is a `:compilers` list, you should append `:rustler` to it.
- Add your crate to the `rustler_crates` attribute in the `project function. [See here](https://hexdocs.pm/rustler/basics.html#crate-configuration).
- Your NIF will now build along with your project.
