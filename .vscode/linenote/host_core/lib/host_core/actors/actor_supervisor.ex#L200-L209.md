## Opportunity for refactoring

1, Do not be afraid to create new function, even if they do a simple thing. Read more on this in the book `Designing Elixir Systems With OTP`.

    - With this, this function can be refactored in a way that makes it easier to read and maintain like so:

    ```elixir
    def live_update(ref, span_ctx \\ nil) do
        # code before ....

        Enum.each(targets, &do_live_update(&1, bytes, new_claims, ref, span_ctx))

        # rest of the code ....
    end

    defp do_live_update(pid, bytes, claims, ref, ctx) do
        bytes
        |> IO.iodata_to_binary()
        |> then(&ActorModule.live_update(pid, &1, claims, ref, ctx))
    end

    ```
