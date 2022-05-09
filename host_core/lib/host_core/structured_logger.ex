defmodule HostCore.StructuredLogger do
  @moduledoc """
  HostCore.StructuredLogger formats any incoming messages into JSON.
  
  The key difference between this logger and others is that it uses erlang handlers instead of elixir backends.
  Because the Elixir Backend interface for logging always returns the message as binary data, it is not
  possible to format it so that it can be decoded in a single pass in 1.11.4. With this logger, the output
  can be fully decoded into the appropriate types/terms.
  
  As it can parse both the message and the metadata, this formatter will merge the two into a relatively
  flat structure. For instance, the mfa, ip, user_id, and guid are from metadata, while the rest are from
  the plug request. This makes it easier to write queries on the backend system.
  
      {"duration":126.472,"guid":"03de7c92-cdbf-4f67-ad10-6abd51ef634c","headers":{},"ip":"1.2.3.4","level":"info",
      "method":"GET","mfa":"StructuredLogger.Plugs.Logger.call/2","params":{},"path":"/","pid":"#PID<0.16365.0>",
      "request_id":"Fm5q11B9tgEmrLEAAZGB","status":200,"time":"2021-03-21T17:13:09.400033Z","user_id":8}
  
  Note that in development where you might want to see a well-formatted stacktrace of a 500 error or exception,
  you might want to continue using Logger for the console. Any exceptions will be put into a JSON format of
  {"level" => level, "metadata" => metadata, "msg" => report}
  
  ## Installation
  In the MyApp.Application.start/2, add the log handler for the formatter. Note that you may want to remove
  the Logger to avoid double logging.
  
      :logger.add_handler(:structured_logger, :logger_std_h, %{formatter: {HostCore.StructuredLogger.FormatterJson, []}, level: :info})
      :logger.remove_handler(Logger)
  
  ### Logging
  
  Like normal, just use Logger.log. Maps and Keyword lists are supported.
      Logger.log(:info, %{"params" => %{"a" => "b"}, "duration" => 10})
  
  ## Credits
  
  https://github.com/elixir-metadata-logger/metadata_logger
  https://github.com/navinpeiris/logster
  https://elixirforum.com/t/structured-logging-for-liveview-handle-params-and-channels/38333/5
  https://elixirforum.com/t/structured-logging-for-liveview-handle-params-and-channels/38333/9
  
  ## NB
  
  We've had to make a few changes (like removing status reports from supervisors) because the report
  format doesn't encode to JSON. Otherwise this is largely the same as originally found.
  
  """
end

defmodule HostCore.StructuredLogger.FormatterJson do
  require Logger

  @doc """
  Only for use with the erlang log handler.
  Any formatted exception reports with stacktraces that are normally shown on 500 errors are no longer available.
  The exceptions will be wrapped in the json formatter.
  """
  def format(%{level: level, msg: msg, meta: meta}, _config) do
    # If it doesn't encode, it is likely an exception being thrown with a weird report
    # https://github.com/elixir-lang/elixir/blob/a362e11e20b03b5ca7430ec1f6b4279baf892840/lib/logger/lib/logger/handler.ex#L229
    # To successfully format, we'd need to do something like:
    # defp encode_msg( {:report, %{label: label, report: report} = complete} ) when map_size(complete) == 2 do
    #   case Logger.Translator.translate(:debug, "unused", :report, {label, report}) do
    #   etc.
    # However, these are being encoded, not for display in dev, so not sure why we need to be too careful here.
    try do
      mfa = encode_meta(meta)
      encoded_msg = encode_msg(msg)

      x =
        log_to_map(level, meta)
        |> Map.merge(mfa)
        |> Map.merge(encoded_msg)
        |> scrub

      [Jason.encode_to_iodata!(x), "\n"]
    rescue
      e ->
        # Give a full dump here
        rescue_data = %{
          "level" => level,
          "meta" => inspect(meta),
          "msg" => inspect(msg),
          "log_error" => inspect(e)
        }

        [Jason.encode_to_iodata!(rescue_data), "\n"]
    end
  end

  defp encode_msg({:string, string}), do: %{"msg" => string}

  defp encode_msg({:report, _report}),
    do: %{"msg" => "reports are unused"}

  defp encode_msg({format, terms}),
    do: %{"msg" => format |> Logger.Utils.scan_inspect(terms, :infinity) |> :io_lib.build_text()}

  defp encode_meta(%{mfa: {m, f, a}}), do: %{mfa: "#{inspect(m)}.#{f}/#{a}"}
  # defp encode_meta(_m), do: %{}

  # https://github.com/elixir-metadata-logger/metadata_logger
  @spec log_to_map(Logger.level(), list[keyword]) :: map()
  def log_to_map(level, metadata) do
    m =
      with m <- Enum.into(metadata, %{}),
           m <- Map.drop(m, [:error_logger, :mfa, :report_cb]),
           {app, m} <- Map.pop(m, :application),
           {module, m} <- Map.pop(m, :module),
           {function, m} <- Map.pop(m, :function),
           {file, m} <- Map.pop(m, :file),
           {line, m} <- Map.pop(m, :line),
           {pid, m} <- Map.pop(m, :pid),
           {gl, m} <- Map.pop(m, :gl),
           {ancestors, m} <- Map.pop(m, :ancestors),
           {callers, m} <- Map.pop(m, :callers),
           {crash_reason, m} <- Map.pop(m, :crash_reason),
           {initial_call, m} <- Map.pop(m, :initial_call),
           {domain, m} <- Map.pop(m, :domain),
           {time, m} <- Map.pop(m, :time),
           {registered_name, m} <- Map.pop(m, :registered_name) do
        m
        |> put_val(:host_id, HostCore.Host.host_key())
        |> put_val(:lattice_id, HostCore.Host.lattice_prefix())
        |> put_val(:app, app)
        |> put_val(:module, module)
        |> put_val(:function, function)
        |> put_val(:file, to_string(file))
        |> put_val(:line, line)
        |> put_val(:pid, nil_or_inspect(pid))
        |> put_val(:gl, nil_or_inspect(gl))
        |> put_val(:crash_reason, nil_or_inspect(crash_reason))
        |> put_val(:initial_call, nil_or_inspect(initial_call))
        |> put_val(:registered_name, nil_or_inspect(registered_name))
        |> put_val(:domain, domain)
        |> put_val(:ancestors, nil_or_inspect_list(ancestors))
        |> put_val(:callers, nil_or_inspect_list(callers))
        |> put_val(:time, transform_timestamp(time))
      end
      |> Map.put(:level, level)

    m
  end

  defp nil_or_inspect(nil), do: nil
  defp nil_or_inspect(val), do: inspect(val)

  defp nil_or_inspect_list(nil), do: nil
  defp nil_or_inspect_list(val), do: Enum.map(val, &inspect/1)

  defp put_val(map, _key, nil), do: map
  defp put_val(map, key, val), do: Map.put(map, key, val)

  defp transform_timestamp({{y, month, d}, {h, minutes, s, mil}}) do
    {:ok, dt} = NaiveDateTime.new(y, month, d, h, minutes, s, mil)
    NaiveDateTime.to_iso8601(dt)
  end

  defp transform_timestamp(t) do
    DateTime.from_unix!(t, :microsecond)
    |> DateTime.to_iso8601()
  end

  defp scrub(map) do
    map
    |> Map.delete(:function)
    |> Map.delete(:logger_formatter)
    |> Map.delete(:file)
    |> Map.delete(:line)
    |> Map.delete(:gl)
    |> Map.delete(:label)
    |> Map.delete(:report)
    |> Map.delete(:domain)
  end
end
