defmodule HostCore.Vhost.FilesConfigProvider do
  @moduledoc """
  A configuration provider that loads configuration from a file.
  The file is expected to be either in json, toml or yml/yaml format.
  """

  defstruct paths: [], bindings: []

  defimpl Vapor.Provider do
    require Logger

    def load(provider) do
      res =
        provider.paths
        |> Enum.reduce(%{}, fn file, acc -> Map.merge(acc, load_file(file)) end)
        |> apply_bindings(provider.bindings)

      {:ok, res}
    end

    defp load_file(file) do
      format = format(file)

      case File.read(file) do
        {:ok, contents} ->
          Logger.debug("Reading configuration file #{file}")

          case decode(contents, format) do
            {:ok, decoded} ->
              decoded

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    end

    defp apply_bindings(premap, bindings) do
      bound =
        bindings
        |> Enum.map(&normalize_binding/1)
        |> Enum.map(&create_binding(&1, premap))
        |> Enum.into(%{})

      bound
      |> Enum.reject(fn {_, data} -> data.val == :missing end)
      |> Enum.map(fn {name, data} -> {name, data.val} end)
      |> Enum.into(%{})
    end

    defp create_binding({name, data}, envs) do
      case get_in(envs, List.wrap(data.env)) do
        nil ->
          val =
            if data.opts[:default] != nil do
              data.opts[:default]
            else
              if data.opts[:required], do: :missing, else: nil
            end

          {name, %{data | val: val}}

        env ->
          {name, %{data | val: data.opts[:map].(env)}}
      end
    end

    defp format(path) do
      case Path.extname(path) do
        ".json" ->
          :json

        ".toml" ->
          :toml

        extension when extension in [".yaml", ".yml"] ->
          :yaml

        _ ->
          raise HostCore.ConfigFileFormatNotFoundError, path
      end
    end

    defp decode("", _format) do
      {:ok, %{}}
    end

    defp decode(str, format) do
      case format do
        :json ->
          Jason.decode(str)

        :toml ->
          Toml.decode(str)

        :yaml ->
          YamlElixir.read_from_string(str)
      end
    end

    defp normalize_binding({name, variable}) do
      {name, %{val: nil, env: variable, opts: default_opts()}}
    end

    defp normalize_binding({name, variable, opts}) do
      {name, %{val: nil, env: variable, opts: Keyword.merge(default_opts(), opts)}}
    end

    defp default_opts do
      [
        map: fn x -> x end,
        default: nil,
        required: true
      ]
    end
  end
end
