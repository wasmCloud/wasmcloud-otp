## Opportunity for refactoring

- Use `Jason.decode!/2` with the options, `[key: :atoms!]` instead of the call to `atomize/1`

**Note**

Remember that atoms are not garbage collected, as such, decoding to atoms can be risky. Only do so cautiously.
