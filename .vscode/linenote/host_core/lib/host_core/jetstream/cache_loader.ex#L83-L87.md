## Observation

The application makes the use of `Registry` to develop a custom PubSub of sorts.

While this is okay, I have the following questions:

1. Why was this decision taken?
2. Were other alternatives considered before opting for a custom PubSub using registry?

## Recommendations

1. Phoenix provides a good PubSub library that can be used: [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)

   - Despite the name, it can be used independently outside of Phoenix in normal applications such as this.

   - Using Phoenix offers a number of advantages over rolling out your own custom PubSub. Read the documentations for more information about how to use it.
