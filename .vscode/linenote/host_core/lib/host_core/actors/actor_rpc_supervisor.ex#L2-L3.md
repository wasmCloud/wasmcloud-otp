## Opportunity for refactor:

1. Follow the stylistic guide [here](https://github.com/christopheradams/elixir_style_guide#modules) when defining modules

## Questions:

1. What is the intended use for this supervisor?

   a. Is it being used to start and/end the Gnat.ConsumerSupervisor dynamically (started or ended on demand)

   b. Is it meant to be static? (this means that it defines a given number
   of child specs that is definite and known before hand)

### Recommendations:

If the supervisor is meant to start the children dynamically, then usage of the `DynamicSupervisor` is best.

Using the DynamicSupervisor, will allow for the easier starting and terminating of the children just be returning `:stop` from any of the callbacks of the child.

It will also eliminate the need of the `stop_rpc_subscriber/1` function, as stopping a child process also deletes it.
