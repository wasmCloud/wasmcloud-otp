## Opportunity for refactoring

Return the content as a whole and avoid the duplicate calls to the Agent (Keep in mind the get call to an Agent is a blocking process).

With the content, you can now pattern match on the values thet you need

```elixir
%{claims: claims, instance_id: i_id} = Agent.get(agent, & &1)

```
