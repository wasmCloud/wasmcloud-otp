## Opportunity for refactor

1. While the `with` clause here works okay, the usage is something that can be done with `case` instead

   ### when to reach for with

   1. When you want to chain multiple calls impure function calls together, where the pipe operator cannot work

      ```elixir
          with {:ok, value} <- some_operation(),
              {:ok, value} <- another_operation(value)
              {:ok, value} <- some_other_operation(value) do
              # do something ...

          else
              {:error, _} -> do_something()

              _other -> do_something_else()
          end

      ```

   2. When whatever operation you want to perform does something and you don't need to handle the else clause, as that will be handled by the caller

      ```elixir
      def do_something(value) do
          case perform_action(value) do
              {:ok, _} = res -> res
              {:error, _} = err -> err
          end
      end

      defp perfrom_do_something(value) do
          with {:ok, value} <- do_something(value) do
              IO.puts("Got #{inspect(value)}")
          end
      end
      ```

   ## Reccomendations

   1. Whenever you realise that the `with` has only one else clause, then use `case` instead

      ```elixir
          # don't do
          with {:ok, value} <- do_something do
              # do domething
          else
              {:error, error} ->
                  # maybe log error
          end

          # instead do
          case do_something() do
              {:ok, _value} ->
                  # do something

              {:error, _error} ->
                  # maybe log error
          end

      ```

   2. In order to ensure that this consisntency is observed, add `:credo` to your mix.exs dependencies and configure it to use this check [Credo.Check.Readability.WithSingleClause](https://hexdocs.pm/credo/Credo.Check.Readability.WithSingleClause.html)

2. This code, uses a lot of nesting of cases, making it really hard to follow, read and eventually maintain. Another effect of this, is that the functions are getting really long as well

   (This code smell is something that is been observed throughou this module and also the code base)

   ### Reccomendations

   1. Write shorter functions that are concise and do one thing at a time and also that provide a single level of abstraction.

      As a guideline, I know it's time to break out a new function when:

      a. find that I need to use a `case` inside a function body in which the new `case` will not the only one
      b. find that I need to ud an `if` statement that is longer than one line and also not the only statement in the function
      c. find the I need to use a `with` statement and it's not the only `with` statement in the function body
      d. Anytime, I need to do a nesting of any of the above statements

   ### Possible refactor

   ```elixir
    @impl GenServer
    def handle_call({:handle_incoming_rpc. msg}, _from, agent) do
        # code before this line ....
        {ir, inv} = unpack_msg_body(inv, body, iid)

        # remember to aslways ensure your task is supervised
        Task.Supervisor.start_child(SomeNameSupervisor, fn ->
            publish_invocation_result(inv, ir)
        end)

        {:reply, {:ok, to_binary(ir)}, agent}
    end

    defp to_binary(ir) do
        ir
        |> Msgpax.pack!()
        |> IO.iodata_to_binary()
    end

    defp unpack_msg_body(inv, body, iid) do
        case Msgpax.unpack(body) do
            {:ok, inv} ->
                Tracer.set_attribute("invocation_id", inv["id"])

                issuers = HostCore.Host.cluster_issuers()
                validate_anti_fogery(body, issuers)

            _ ->
                Trace.set_status(:error, "Failed to deserialize msgpack invocation")

                ir = %{
                    msg: nil,
                    invocation_id: "",
                    error: "Failed to deserialize msgpack invocation",
                    instance_id: iid
                }

                {ir, nil}
        end
    end

    defp validate_anti_fogery(body, issuers, agent, inv, iid) do
        case HostCore.WasmCloud.Native.validate_antiforgery(body, issuers) do
            {:error, msg} ->
                Logger.error("Invocation failed anti-forgery validation check: #{msg}",
                    invocation_id: inv["id"]
                )
                Tracer.set_status(:error, "Anti-forgery check failed #{msg}")

                ir = %{
                    msg: nil,
                    invocation_id: inv["id"],
                    error: msg,
                    instance_id: iid
                }

                {ir, inv}

            _other ->
                do_validate_invocation(agent, inv)
        end
    end

    defp do_validate_invoication(agent, inv, iid) do
        case do_perform_invocation(agent, inv, iid) do
            {:ok, response} ->
                Tracer.set_status(:ok, "")

                ir = %{
                    msg: response,
                     instance_id: iid,
                     invocation_id: inv["id"],
                     content_length: byte_size(response)
                }

                {chunk_inv_response(ir), inv}

            {:error, error} ->
                Logger.error("Invocation failure: #{error}", invocation_id: inv["id"])
                Tracer.set_status(:error, "Invocation failure: #{error}")

                ir = %{
                    msg: nil,
                     error: error,
                     instance_id: iid,
                     invocation_id: inv["id"]
                }

                {ir, inv}
        end
    end

    defp do_perform_invoication(agent, %{"origin" => origin, "target" => target, "id" => id, "content_length" => len} = inv) do
        msg = Map.get(inv, "msg", <<>>)

        agent
        |> validate_invocation(origin["link_name"], target)
        |> policy_check_invocation(origin, target)
        |> perform_invocation(id, len, msg)
        |> IO.iodata_to_binary()
    end
   ```

   **Note**

   The above is just one of the many ways that it can be refactored.
