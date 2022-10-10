### Opportunity for refactoring

(Optional)

This function as it is if correct and functional. However, the nesting of `if` with `case` and the multiple `ifs` makes it hard to follow.

**Note**

1. While defining any function, make sure that the cognitive load required for figure out what the function is doing is as little as possible.

   - Basically, this means keep your function as simple as possible (Follow the KISS rule, Keep It Simple Stupid)

2. Ensure your function maintains a sigulare responsibilty.

   - This function as is, is doing at least 3 seperate things:

   1. Getting the key by checking whether or not the reference starts with "V"

   2. Looking up key from the Refmaps.Manager if not
   3. Checking whether of not the key is valid and returning whether or not the provider is running

### Possible refactors

```elixir
def provider_running?(reference, link_name) do
    reference
    |> get_reference_key()
    |> is_running?(link_name)
end

defp get_reference_key(reference) do
    if String.starts_with?(reference, "V") do
        reference
    else
        look_up_reference_key(reference)
    end
end

defp lookup_reference_key(ref) do
    case HostCore.Refmaps.Manager.lookup_refmap(ref) do
        {:ok, {_, pk}} -> pk
        _ -> ""
    end
end

defp is_running?(key, _) when byte_size(key) == 0, do: false

defp is_running?(key, link_name) do
    case Registry.lookup(ProviderRegistry, {key, link_name}) do
        [{_, _}] -> true
        _ -> false
    end
end

```
