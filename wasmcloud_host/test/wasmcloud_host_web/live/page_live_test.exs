defmodule WasmcloudHostWeb.PageLiveTest do
  use WasmcloudHostWeb.ConnCase

  import Phoenix.LiveViewTest

  # Not applicable with a full page
  # test "disconnected and connected render", %{conn: conn} do
  #   {:ok, page_live, disconnected_html} = live(conn, "/")
  #   assert disconnected_html =~ "Welcome to Phoenix!"
  #   assert render(page_live) =~ "Welcome to Phoenix!"
  # end
end
