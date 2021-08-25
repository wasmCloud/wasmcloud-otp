defmodule WasmcloudHostWeb.PageLive do
  use WasmcloudHostWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    WasmcloudHostWeb.Endpoint.subscribe("lattice:state")
    WasmcloudHostWeb.Endpoint.subscribe("frontend")

    {:ok,
     socket
     |> assign(
       hosts: WasmcloudHost.Lattice.StateMonitor.get_hosts(),
       linkdefs: WasmcloudHost.Lattice.StateMonitor.get_linkdefs(),
       ocirefs: WasmcloudHost.Lattice.StateMonitor.get_ocirefs(),
       claims: WasmcloudHost.Lattice.StateMonitor.get_claims(),
       open_modal: nil,
       selected_host: nil
     )}
  end

  @impl true
  def handle_info({:linkdefs, linkdefs}, socket) do
    {:noreply, assign(socket, linkdefs: linkdefs)}
  end

  def handle_info({:claims, claims}, socket) do
    {:noreply, assign(socket, claims: claims)}
  end

  def handle_info({:ocirefs, ocirefs}, socket) do
    {:noreply, assign(socket, ocirefs: ocirefs)}
  end

  def handle_info({:hosts, hosts}, socket) do
    {:noreply, assign(socket, hosts: hosts)}
  end

  def handle_info({:open_modal, modal}, socket) do
    {:noreply, assign(socket, open_modal: modal)}
  end

  def handle_info(:hide_modal, socket) do
    {:noreply, assign(socket, open_modal: nil)}
  end

  @impl true
  def handle_event("select_host", %{"host" => host}, socket) do
    {:noreply, assign(socket, :selected_host, host)}
  end

  def handle_event("show_all_hosts", _values, socket) do
    {:noreply, assign(socket, :selected_host, nil)}
  end

  @impl true
  def handle_event("show_modal", %{"modal" => modal}, socket) do
    {:noreply, assign(socket, :open_modal, modal)}
  end

  @impl true
  def handle_event(
        "show_modal",
        modal,
        socket
      ) do
    {:noreply, assign(socket, :open_modal, modal)}
  end

  @impl true
  def handle_event("hide_modal", _value, socket) do
    {:noreply, assign(socket, :open_modal, nil)}
  end
end
