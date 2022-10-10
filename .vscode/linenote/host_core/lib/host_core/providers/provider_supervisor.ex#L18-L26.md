## Observation

This function head takes 7 arguments in order to perform it's task.

While this might seem okay, it does have the unintended consequence of making this function hard to read, because of the cognitive load required to remember all the arguments.

## Recommendations

1. Whenever you find that your functions requires more than 3 arguments, consider using a map or keyword list, and the do pattern matching on it

   - Read more on the importance of passing fewer arguments to functions on the book `Clean Code`
