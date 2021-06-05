defmodule WasmcloudHostWeb.PageLive do
  use WasmcloudHostWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    WasmcloudHostWeb.Endpoint.subscribe "lattice:state"

    {:ok, socket |> assign(
       actors: WasmcloudHost.Lattice.StateMonitor.get_actors() |> summarize_actors(),
       providers: WasmcloudHost.Lattice.StateMonitor.get_providers(),
       linkdefs: WasmcloudHost.Lattice.StateMonitor.get_linkdefs(),
       claims: WasmcloudHost.Lattice.StateMonitor.get_claims(),
      )
    }
  end

  @impl true
  def handle_info({:actors, actors}, socket) do

    {:noreply, assign(socket, actors: actors |> summarize_actors() )}
  end

  def handle_info({:providers, providers}, socket) do
    {:noreply, assign(socket, providers: providers )}
  end

  def handle_info({:linkdefs, linkdefs}, socket) do
    {:noreply, assign(socket, linkdefs: linkdefs )}
  end

  def handle_info({:claims, claims}, socket) do
    {:noreply, assign(socket, claims: claims )}
  end

  # Gets the sum of instance counts from all hosts on which actor
  # is running, returns {"Mxxx", count}
  defp summarize_actors(actors) do
    Enum.map(actors, fn {k, v} -> {k, Enum.sum(Map.values(v))} end)
  end

end
