defmodule HostCore.ConsoleLogger do
  @moduledoc """
  HostCore.ConsoleLogger is the default logger. It functions almost the same as the default
  Logger.Formatter, with a notable difference: all metadata keys are printed before the message,
  filtering built-in keys, such as :erl_level, :application, :mfa, and so on. If any of these
  metadata keys should be printed, this logger will need to be modified.

  Example statement and accompanying formatted message:

    Logger.info(
      "Started wasmCloud OTP Host Runtime",
      version: "#{to_string(Application.spec(:host_core, :vsn))}"
    )

    12:44:43.028 [info] version=0.60.0 Started wasmCloud OTP Host Runtime

  """

  require Logger

  @excluded_keys MapSet.new([
                   :erl_level,
                   :application,
                   :domain,
                   :file,
                   :function,
                   :gl,
                   :line,
                   :mfa,
                   :module,
                   :pid,
                   :time
                 ])

  @without_metadata_pattern Logger.Formatter.compile("$time [$level] $message\n")
  @with_metadata_pattern Logger.Formatter.compile("$time [$level] $metadata$message\n")

  def format(level, message, timestamp, metadata) do
    filtered_metadata = Enum.reject(metadata, fn {k, _v} -> MapSet.member?(@excluded_keys, k) end)

    pattern =
      case filtered_metadata do
        [] -> @without_metadata_pattern
        _ -> @with_metadata_pattern
      end

    Logger.Formatter.format(pattern, level, message, timestamp, filtered_metadata)
  rescue
    err -> "ERROR: FAILED TO FORMAT LOG MESSAGE! #{inspect(err)}\n"
  end
end
