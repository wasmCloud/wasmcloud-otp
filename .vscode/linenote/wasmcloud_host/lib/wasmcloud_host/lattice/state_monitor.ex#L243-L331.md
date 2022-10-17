## Observations

1. This function is too long and does a number of things hence affecting its readability.

### Recommendations:

1. Breakout this function into smaller functions.

   - A good place to start would be to define private functions for `Enum.reduce/3` function calls

   - Also, breakout the cases into their own functions as well.
