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
    post "/define_link", LinkdefsController, :define_link
  end

  # Other scopes may use custom stacks.
  # scope "/api", WasmcloudHostWeb do
  #   pipe_through :api
  # end
end
