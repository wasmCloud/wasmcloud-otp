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
      <td>
        <%= @provider_name %>
      </td>
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
      <td>
        <button id="copy_provider_id_<%= @provider %>_<%= @link_name %>_<%= @host_id %>" class="btn btn-sm btn-primary id-monospace"
          data-toggle="tooltip" data-placement="top" title data-original-title="Copy Provider ID"
          onClick="navigator.clipboard.writeText('<%= @provider %>')">
          <%= String.slice(@provider, 0..4) %>&#8230;
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button>
        <button class="btn btn-sm btn-danger" id="delete_provider_<%= @provider %>_<%= @link_name %>_<%= @host_id %>"
          data-toggle="tooltip" data-placement="top" title data-original-title="Delete Provider" phx-target="<%= @myself %>"
          phx-click="delete_provider" phx-value-provider="<%= @provider %>" phx-value-link_name="<%= @link_name %>"
          phx-value-host_id="<%= @host_id %>">
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-trash"></use>
          </svg>
        </button>
      </td>
    </tr>
    <script>
      createTooltip(document.getElementById("copy_provider_id_<%= @provider %>_<%= @link_name %>_<%= @host_id %>"))
      createTooltip(document.getElementById("copy_host_id_<%= @provider %>_<%= @link_name %>_<%= @host_id %>"))
      createTooltip(document.getElementById("delete_provider_<%= @provider %>_<%= @link_name %>_<%= @host_id %>"))
    </script>
    """
  end
end
