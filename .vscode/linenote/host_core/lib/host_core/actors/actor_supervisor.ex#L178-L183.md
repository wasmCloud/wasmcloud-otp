## Observations and opportunities for refactoring

1. While only cited here, the problem of defining functions with more than 3 arguments is seen throughout the codebase. (this is not a big problem but it does lead to readability issues)

2. There's an attempt to call functions while passing arguments to function calls (affects readability issues)

### Recommendations

1. Whenever possible limit the number of arguments passed to a function to 3 and if more are needed, consider the use of maps, or keyword lists.

   - Of course, use this rule depending on the situation you're dealing with.

   ```elixir
   # prefer not to do this
   def some_function(arg1, arg2, arg3, arg4, arg5, argN) do
       # code
   end

   # prefer this, if the number of args is potentially more that 3
   # you can use pattern matching here if needed
   def some_function(%{} = oprs) do
       # code
   end

   ```

2. Always prefer the creation of intermediate variables when passing arguments to functions. Again, excercise judgement based on the scenario that works for you. However, ensure that the code will be readable and maintainable in the end

   ```elixir
   latest = HostCore.Oci.allow_latest()
   insecure = HostCore.Oci.allow_insecure()

   with {:ok, bytes} <- HostCore.WasmCloud.get_oci_bytes(creds, ref, latest, insecure),

   # rest of the code ....

   ```
