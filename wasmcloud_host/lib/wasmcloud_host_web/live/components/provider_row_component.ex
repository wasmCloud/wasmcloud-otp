defmodule ProviderRowComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, socket}
  end

  def handle_event(
        "delete_provider",
        %{"provider" => provider, "link_name" => link_name, "host_id" => host_id},
        socket
      ) do
    WasmcloudHost.Lattice.ControlInterface.stop_provider(provider, link_name, host_id)
    {:noreply, socket}
  end

  def render(assigns) do
    ~L"""
    <tr>
      <td><%= @link_name %></td>
      <td><%= @contract_id %></td>
      <td>
        <span class="badge <%= case @status do
            "Awaiting" -> "badge-secondary"
            "Healthy" -> "badge-success"
            "Unhealthy" -> "badge-danger"
            end%>">
          <%= @status %></span>
      </td>
      <td><button class="btn btn-primary btn-sm id-monospace" type="button" onClick="navigator.clipboard.writeText('<%= @provider %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
          <%= String.slice(@provider, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button></td>
      <td>
        <button class="btn btn-primary btn-sm id-monospace" type="button" onClick="navigator.clipboard.writeText('<%= @host_id %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
          <%= String.slice(@host_id, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button>
      </td>
      <td>
      <button class="btn btn-sm btn-danger"
        data-toggle="tooltip"
        data-placement="top"
        title data-original-title="Delete Provider"
        phx-target="<%= @myself %>"
        phx-click="delete_provider"
        phx-value-provider="<%= @provider %>"
        phx-value-link_name="<%= @link_name %>"
        phx-value-host_id="<%= @host_id %>">
      <svg class="c-icon" style="color: white">
        <use xlink:href="/coreui/free.svg#cil-trash"></use>
      </svg>
    </button>
      </td>
    </tr>
    """
  end
end
