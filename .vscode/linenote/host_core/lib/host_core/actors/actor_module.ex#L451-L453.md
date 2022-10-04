## Opportunity for refactoring

- While as it currently is, it works, refactoring this to use `Enum.any/2` will make the function much more readable

```elixir
def imports_wasi(imports_map) do
    imports_map
    |> Map.keys()
    |> Enum.any?(fn ns -> String.contains?(ns, "wasi) end)
end

```
