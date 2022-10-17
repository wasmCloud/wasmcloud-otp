## Opportunity for refactoring

As it is currently implemented, it works and is okay.

However, this could be imporved on the basis that `Map.get/3` returns `nil` when the key does not exist in the map.

### Possible refactor

1. Because this code is checking using an `if` which only returns the first clause on truthy values.

   - We can take advantage of this like so:

   ```elixir
   if Map.get(resp, "accepted") do
       :ok
   else
       {:error, Map.get(resp, "error", "")}
   end

   ```

2. The block above is also been repeated a lot in this module, hence, violating the `DRY` principle.

   - This can be fixed by extracting this check to a different function similar to:

   ```elixir
   def check_reponse(resp) do
       if Map.get(resp, "accepted") do
           :ok
       else
           {:error, Map.get(resp, "error", "")}
       end
   end

   ```
