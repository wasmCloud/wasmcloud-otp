## Opportunity for refactoring

1. Consider making use of `alias` as much as possible and whenever the situation is possible. Doing this will make your code more readable

   - In this example, there's a good opportunity to use the alias command

   ```elixir
   alias HostCore.{Claims, Refmaps}

   # with the alias safely done, you can do
   Claims.Manager.put_claims()
   ```

## Recommendations

1. Ensuring code consistency across the teams, you can add `credo` to your application and then use the [Credo.Check.Readability.AliasOrder](Credo.Check.Readability.AliasOrder) and [Credo.Check.Readability.AliasAs](https://hexdocs.pm/credo/Credo.Check.Readability.AliasAs.html)

**Note**

Remember that while `Credo` ensures consistency, add only the checks that make sense for your project and the checks are more or less suggestions on what the authors of the library think is best.
