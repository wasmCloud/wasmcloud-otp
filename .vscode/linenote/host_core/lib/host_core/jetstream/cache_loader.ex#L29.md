### Opportunity for refactor

`Jason.decode/2` with the option of `[keys: :atoms]` uses `String.to_atom/1` to convert the keys to atoms.

This means that if the atoms do not exist, it will create new atoms everytime. A danger of this is that it might deplete the memory because atoms are not garbage collected

## Recommedations

1. If there's absolute certainty the the atoms created by this call already exist, then use `Jason.decode/2` with options `[keys: :atoms!]` to ensure that the atoms are created using `String.to_existing_atom/1`

2. If unsure, then use `Jason.decode/2` without any options, and let it default to using stringed keys.

   - Of course with this change, you have to make sure everywhere that the atom keys are accessed from the decoded json is changed to use the stringed keys instead
