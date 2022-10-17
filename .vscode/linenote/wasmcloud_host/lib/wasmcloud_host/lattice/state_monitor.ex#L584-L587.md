## Questions

1. Is there a possibility that the `:count` can be 0?

2. If yes, then is it acceptable for the new count value to be a negative number?

- While the above might be an edge case, especially based on the current implementation of the line `Map.get(actor_map, :count, nil)`, consideration for if this can return `0` is important as well
