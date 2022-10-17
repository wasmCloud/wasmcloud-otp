## Opportunity for refactoring

- Again, here, we can take advantage of the `truthy` check that `if` does when deciding which clause to run

- Everything in Elixir is considered truthy except for `false` or `nil`

- With the above knowledge, this code could be refactored to:

  ```elixir
  if host_id, do: {:ok, host_id}, else: {:error, "Auction response did not contain Host ID"}

  ```
