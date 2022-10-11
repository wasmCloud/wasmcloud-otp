## Questions

1. Why is this `handle_continue/2` callback being implemented if it's doing nothing?

2. If it was meant to do something, has it been decided on what that will be?

## Recommendations

1. If it does nothing, remove it from the GenServer

2. If it's meant to do something in the future, provide comments on what that entails and why it's yet to be implemented.

   - This is to prevent any future developers who have no prior knowledge from removing it
