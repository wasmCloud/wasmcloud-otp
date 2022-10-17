## Opportunity for refactoring

Because this is a live component, the `mount/1` callback can actually be ignored.

This means that the most important callback is the `update/2` callback where the component can be prepared.
