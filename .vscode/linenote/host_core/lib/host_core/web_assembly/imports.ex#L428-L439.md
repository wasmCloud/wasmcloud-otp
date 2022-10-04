## Observation

This is an attempt to start a task that is one off (fire and forget kind of a request).

However, this task in itself not supervised at all and should it fail, it will not be restarted at all.

## Recommendation

While the `Task` module does offer the ability to spawn processes, [it is always recommeded that you start any task under a supervision tree](https://hexdocs.pm/elixir/1.13/Task.html#module-dynamically-supervised-tasks)

**Notes**

Never start a process that is not supervised within your application.

## Refactoring

Whenever a need for using the `Task` module arises, always reach for the `Task.Supervisor` module which allows for supervision of your task process

This can, thus, be refactored to:

```elixir
## Inside the file the implements `Use Application` add the following to the supervision tree

childred = [
    # ...children before
    # given an appropriate name
    {Task.Supervisor, name: SomeNameSupervisor}

    # ...children before
]


# In this file, replace the task module with:
Task.Supervisor.start_child(SomeNameSupervisor, fn ->
    publish_invocation_result(
        actor,
        namespace,
        binding,
        operation,
        byte_size(payload),
        target_type,
        target_key,
        res
      )
end)

```
