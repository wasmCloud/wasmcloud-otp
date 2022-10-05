## Opportunity for refactoring

Given that this module is an Elixir GenServer, it means that the result of calling `GenServer.start_link/2` of your child module will always return `{:ok, pid}`

As such, this clause can safely be removed without any effect to the application.

**Note**

For a more detailed discusssion, find it [here](https://elixirforum.com/t/how-to-return-extra-information-when-starting-a-genserver/13942)
