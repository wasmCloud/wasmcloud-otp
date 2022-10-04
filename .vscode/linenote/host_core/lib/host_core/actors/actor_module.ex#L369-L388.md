## Opportunity for refactoring

While this okay, the code does nest a `case` inside of an `if`.

This can be refactored to move the case into its own function

```elixir
defp check_dechunk_inv(inv_id, content_length, bytes) do
    if content_lenght > byte_size(bytes) do
        maybe_dechunck(inv_id)
    else
        bytes
    end
end

defp maybe_dechunk_inv(inv_id, content_length) do
    Logger.debug("Dechunking #{content_length} from object store for #{inv_id}",
    invocation_id: inv_id)

    case HostCore.WasmCloud.Native.dechunk_inv(inv_id) do
        {:ok, bytes} ->
          bytes

        {:error, e} ->
          Logger.error("Failed to dechunk invocation response: #{inspect(e)}")

          <<>>
    end
end

```
