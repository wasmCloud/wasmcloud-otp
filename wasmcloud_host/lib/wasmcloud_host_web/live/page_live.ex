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
       claims: WasmcloudHost.Lattice.StateMonitor.get_claims(),
       open_modal: nil
     )}
  end

  @impl true
  def handle_info({:linkdefs, linkdefs}, socket) do
    {:noreply, assign(socket, linkdefs: linkdefs)}
  end

  def handle_info({:claims, claims}, socket) do
    {:noreply, assign(socket, claims: claims)}
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
