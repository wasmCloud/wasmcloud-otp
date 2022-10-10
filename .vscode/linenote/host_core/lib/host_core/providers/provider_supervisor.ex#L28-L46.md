## Opportunity for refactoring

In this function call, there're attempts to create the maps within the arguments themselves.

    - While this okay, technically, it has the unintended consequence of making the function really hard to read and eventually harder to maintain.

## Recommendations

1. Pull out the argument constructions into their own variables and pass those variables as arguments to the function call.
