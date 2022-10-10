### Observation

This GenServer makes use of `handle_continue/2` to break apart the initialization into 2 distinct steps:

1. `:ensure_streams`
2. `:create_rph_consumer`

#### Questions

1. In the first step, there is a possibility of the creation of the topic failing, for which a return of `{:noreply, state}` is returned.

   - Shouldn't a failure stop this server from running, of course after logging the error?

   - Or shouldn't there be a rescheduling of another trial to try and create the topic after a given number of time?
