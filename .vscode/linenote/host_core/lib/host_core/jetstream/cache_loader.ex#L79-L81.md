## Opportunity for refactoring

This function is actually not needed because `Jason.decode!/2` can change the keys to atoms by passing the opts, `[keys: :atoms!]`

**Note**

The same concern for atoms not been garbage collected applies here.

Hence, ensure that decoding to atom keys is abasolutely necessary and that the atoms exist or else two things might happen:

    1. Run out of memory because the number of atoms created exceed the maximum allowed by the BEAM

    2. If using opts `[keys: :atoms]`, an error will be raised because `String.to_existing_atom/1` raises an error if the atom does not exist
