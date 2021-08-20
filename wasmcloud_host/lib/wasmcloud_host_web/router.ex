defmodule WasmcloudHostWeb.Router do
  use WasmcloudHostWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {WasmcloudHostWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WasmcloudHostWeb do
    pipe_through :browser

    live "/", PageLive, :index
  end

  scope "/metrics", WasmcloudHostWeb do
    pipe_through :browser

    live "/", MetricsLive, :index
  end

  # Other scopes may use custom stacks.
  scope "/api", WasmcloudHostWeb do
    pipe_through :api

    get "/readyz", ProbeController, :ready
    get "/livez", ProbeController, :live
  end
end
