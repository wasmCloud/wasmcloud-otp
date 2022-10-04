## Opportunities for refactoring

1. For all the keys for which is calculated using the `if` statements, refactor them to a seperate functions

   The main reason for this is to ensure:

   1. The function `put_claims/1` is no longer as long as it is
   2. It ensures the function is easy to read and maintainable

   ```elixir
   claims = %{
       call_alias: get_aliases(claims),
       name: get_name(claims),
       caps: get_caps(claims),
   }

   defp get_aliases(%{call_alias: c_alias}) do
       if c_alias, do: c_alias, else: ""
   end

   defp get_name(%{name: name}) do
       if name, do: name, else: ""
   end

   defp get_caps(%{caps: caps}) do
       if caps, do: caps, else: ""
   end

   ## do the same for all the other keys computed
   ```
