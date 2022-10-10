## Implementation Error

**Note**

Supervisors and DynamicSupervisors do not exports the callback `handle_info/2`.

As such, they do not expect the callback to be implemented at all.

### Fix

1. Delete the implementation for `handle_info/2` in this module and any other module that implements the `Supervisor` or `DynamicSupervisor` behaviour.
