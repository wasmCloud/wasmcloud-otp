## Opportunity for refactoring

1. Consider breaking this into different functions with specific responsibilities

2. For the args been sent to the function, consider creating intermediate variables to hold them and pass those to the function call.

3. For the nested `case`, consider breaking those into functions and call those functions as well.

4. Remove the piping into a singular function. Instead use the traditional function call (Only pipe into a chain of pure functions)
