defmodule Washboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Washboard.Worker.start_link(arg)
      # {Washboard.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Washboard.Supervisor]
    IO.puts "Starting Washboard"
    Supervisor.start_link(children, opts)
  end
end
