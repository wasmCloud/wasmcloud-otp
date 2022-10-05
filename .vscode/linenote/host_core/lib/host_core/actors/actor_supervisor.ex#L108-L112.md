## Observations

There is an attempt to trap exists within the DynamicSupervisors, which should then be handled with the `handle_info/2` callback

Supervisors and DynamicSupervisors are special processes whose work is to "monitor" its child processes and then restart them if necessary.

Trying to trap exits in a Supervisor or DynamicSupervisor, thusz becomes a kind of no-op operation

### Problems

1. Supervisors and Dynamic supervisors do not export the `handle_info/2` callback.

   As such, setting the supervisor process to trap exists, means that whenever any of the processes it is supervising exists, the exit message is sent to it and is not being handled, leading to the mailbox filling.

### Fix

1. Remove the call to `Process.flag(:trap_eixt, true)` in the `init/1` callback

2. Delete the `handle_info/2` callback from this DynamiSupervisor
