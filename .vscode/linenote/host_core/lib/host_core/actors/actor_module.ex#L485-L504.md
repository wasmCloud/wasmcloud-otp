## Opportunity for refactoring

As it currently is, this code is hard to read, hence, having the effect of making it harder to maintain as well

### Observations

1. There's an attempt to merge massive function calls, ie. this one, in return types in order to avaoid creation of intermediate varaibles. (this is prevalent throughout the the codebase)

   - An effect of this is that the codebase becomes really hard to read and follow and will in the long run lead to problems with maintainability

2. Instead of creating variables outside of the function calls, this code and and in extension throughout the codebase, there's an attempt to do so in the function calls themselves

   - This, like the above, makes the code really hard to read and by extension really hard to maintain as well.

### Recommendations

1. Remember that code is writtern to be read most of the time, and as such, making it readable should be a priority.

2. Whenever possible or in doubt, create an intermediate variable. This will make the code really easy to read

   ```elixir
       # don't do this
       function_call(
           %{
               key: val,
               key2: val2,
               key3: val3
           },
       )

       # instead do this:
       params = %{
           key: val,
           key2: val2,
           key3: val3
       }

       function_call(params)

   ```

3. For the selected code, we can do a refactor to

   ```elixir
       source = %{
          publicKey: source["public_key"],
          contractId: source["contract_id"],
          linkName: source["link_name"],
          capabilities: source_claims[:caps],
          issuer: source_claims[:iss],
          issuedOn: source_claims[:iat],
          expiresAt: expires_at,
          expired: expired
       }

       target = %{
          publicKey: target["public_key"],
          contractId: target["contract_id"],
          linkName: target["link_name"],
          issuer: target_claims[:iss]
       }

       {{agent, true}, HostCore.Policy.Manager.evaluate_action(source, target)}

   ```
