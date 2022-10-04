## Opprotunity for refactoring

1. Whenever a function is being invoked and it's not been chained to more function, do not use the pipe operator.

   This is because, while it it correct, it affects the readability of the functions.

   ```elixir
   value = "some_value"

   # don't do
   value
   |> some_function()

   # instead do
   some_function(value)

   # only use the pipe operator when chaining multiple function calls
   value
   |> some_function()
   |> another_function()
   |> maybe_another()

   ```

2. The highlighted part can be refactored to:

   ```elixir
   ir = MsgPax.unpack!(res)

   if ir["error"] do
       {0, :host_error, ir["error"]}
   else
       bin =
           ir
           |> check_dechunk()
           |> IO.iodata_to_binary()

       {1, :host_response, bin}
   end

   ```
