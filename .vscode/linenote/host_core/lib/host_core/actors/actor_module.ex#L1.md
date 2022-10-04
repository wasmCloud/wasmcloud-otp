## Observations

1.  This GenServer module does not implement a default `handle_info/2` callback to match every other message sent to it

    ##### Recommendation:

    a. Implement a default `handle_info/2` callback, in order to ensure that the process mailbox does not contain unmatched messages

        ```elixir
        @impl GenServer
        def handle_info(_, state) do
            {:noreply, state}
        end

        ```

2.  While most of the callback's implementation are short and precise, the few that are not are tightly coupled to the module. While this is okay, it does make changing logic or even testing of the individual logic harder as it is coupled to the GenServer.

    An alternative to this would be to decouple it completely like below:

    ```elixir
    defmodule Some.Module do
        use GenServer

        alias Another.Module

        @impl GenServer
        def handle_call(msg, _from, state) do
            res = Module.do_something(msg)

            {:reply, res, new_state}
        end
    end

    ```

    Doing something similar to this ensures that:

    1. Eliminated as much decupling as possible from the GenServer, hence letting the GenServer only define the runtime requirements for the system

    2. Since the logic has been pulled away from the Server, we can easily upgrade and/or unit test the logic without the constraints of the GenServer itself. This is exaplained much better in the book [Testing Elixir](https://pragprog.com/titles/lmelixir/testing-elixir/)
