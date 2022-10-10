## Opportunity for refactoring

(Optional)

While the current spec is okay and works fine, as a matter of preference, specs should also provide for the names of the arguments the functions expects

## Reasoning

1. Specs provide information to the reader about what types of arguments a function expects and what types the function returns

2. Providing variables makes it easy to read the spec and well as providing documentations using tools such as `ex_doc`

### Possible refactoring

```elixir
@spec lookup_link_definition(actor :: String.t, contract_id :: String.t, link_name :: String.t) :: {:ok, link_definition :: map}
def lookup_link_definition(actor, contract_id, link_name) do
    # code
end

```

**Notes**

To ensure consistency within the application, consider the use of credo's []()

The credo check will ensure that all public functions contain a spec definition, allowing for consistency. However, take note that adding this check will require that all public function have specs defined and might be mean refactoring most of the code base.

As such, take such a decision cautiously.
