## Observations

This is function is really long, hence, affecting it's readability and maintainability,

## Recommendations:

1. Break down this function into a smaller concise bits that do one thing and one thing alone (singular responsibility).

## Questions

I noticed that you stop the previous instance before the starting the new one, as such, I have the following questions:

    1. When the new instance fails to start for whatever reason, shouldn't this particular GenServer also be stopped because it's instance is no longer alive?

    2. Or is there a particular reason for keeping it alive still? And if so, given that the old version has already been stopped, shouldn't it be restarted?
