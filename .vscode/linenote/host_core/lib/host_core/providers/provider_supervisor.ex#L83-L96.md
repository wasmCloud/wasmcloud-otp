## Opportunity for refactoring

Because of the function call passed as argument, this function adversely affects its readability.

## Possible fixes

1. Remove the function call passed as the first argument to a seperate variable

   ```elixir
   %{contract_id = cid, claims: %{public_key: pk, revision: rev} = claims} = par
   path = HostCore.WasmCloud.Native.pre_cache_path(pk, rev, cid, link_name)

   start_executable_provider(path, claims, link_name, cid, ref, config_json, annotations)

   ```

2. Remove the function call as first argument and use the pipe operation

   ```elixir
   %{contract_id: cid, claims: %{public_key: pk, revision: rev} = claims} = par

   pk
   |> HostCore.WasmCloud.Native.pre_cache_path(rev, cid, link_name)
   |> start_executable_provider(claims, link_name, cid, config_jaon, annotations)

   ```
