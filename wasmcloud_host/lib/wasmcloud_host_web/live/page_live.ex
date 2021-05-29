defmodule WasmcloudHostWeb.PageLive do
  use WasmcloudHostWeb, :live_view
  require Logger
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    WasmcloudHostWeb.Endpoint.subscribe "lattice:state"
    
    {:ok, socket |> assign(
       actors: WasmcloudHost.Lattice.StateMonitor.get_actors(),
       providers: WasmcloudHost.Lattice.StateMonitor.get_providers(),
       linkdefs: WasmcloudHost.Lattice.StateMonitor.get_linkdefs()
      )
    }
  end

  def handle_info({:actors, actors}, socket) do    
    
    {:noreply, assign(socket, actors: actors )}
  end

  def handle_info({:providers, providers}, socket) do
    {:noreply, assign(socket, providers: providers )}
  end

  def handle_info({:linkdefs, linkdefs}, socket) do
    {:noreply, assign(socket, linkdefs: linkdefs )}
  end

end
