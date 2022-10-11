## Opportunity for refactoring

Currently, this task module is being spawned without a supervisor, even though it's a fire and forget kind of a process

### Recommendation

1. Consider the use of its supervised counterpart `Task.Supervisor.start_child/1`

2. Always ensure that there are no unsupervised processes spawned within your system.

   - This is espsecially true for `Task.start` because it's not linked to the current process and shoult it fail or crash, it will not get restarted or notify the parent process

   - An side effect of this is that you could have false expectation that it did complete successfully, even when it failed.
