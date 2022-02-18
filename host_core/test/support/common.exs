defmodule HostCoreTest.Common do
  require Logger

  def request_http(url, retries) when retries > 0 do
    case HTTPoison.get(url) do
      {:ok, resp} ->
        {:ok, resp}

      _ ->
        Logger.debug("HTTP request failed, retrying in 1000ms, remaining retries #{retries}")
        :timer.sleep(1000)
        request_http(url, retries - 1)
    end
  end

  def request_http(_url, 0) do
    # IO.puts("YO! YOUR HTTP LIBRARY MAY BE MESSED UP, CURL #{url}")
    # :timer.sleep(60000)
    {:error, "Connection refused after retries"}
  end
end
