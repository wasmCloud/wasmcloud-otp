# Refactoring opportunity

Remove the call to `Process.flag(:trap_exit, true)` from the init of the supervisor.

## Reasoning

- Trapping of exists means that the exit messages are converted to messages which are then sent to the trapping process.

- It is expected that the calling process will handle this through the `handle_info/2` callback.

- However, the `Supervisor` and the `DynamicSupervisor` do not have the given callbacks, hence, does not have the desired effect.

### Recommendations

1. Remove this line from this Supervisor and any other supervisors within the application

2. If trapping of processes is a desired effect, do it in any other processes that are not supervisors
