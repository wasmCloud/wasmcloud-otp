## Observations

This module is a GenServer that:

1. Does not export any client functions.

   - As it is currently implemented, other processes do not interact with it at all due to the lack of even a `handle_info/2` from which we could infer it it's send messages directly

2. Does not reschedule anything to be run after a period of time.

### Questions:

1. Why was the decision to make this a GenServer a process?

   - As it is currently implemented, this does not need to be a process at all

2. If, there is a valid reason to make it a GenServer, are there plans to add functionalities to satisfy the observations made above?

### Recommendations:

1. Change this from a process into a normal module that does what is required.
2. If the process is necessary, then from the `handle_continue/2` callbacks, return `{:stop, :normal, state}` once it has completed its task

   - The reason for this is that, as it currently stands the process is still running and using up memory, despite not been need.

   - Returning `{:stop, :normal, state}`, gracefully stops the GenServer once it has finished its task.

   - Remember to also change the restart for this GenServer and make it `:temporary` or `:transient` depending on the requirements of your system
