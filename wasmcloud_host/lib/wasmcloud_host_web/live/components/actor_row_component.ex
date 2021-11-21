defmodule ActorRowComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, socket}
  end

  def handle_event(
        "stop_hotwatch",
        %{"actor_id" => actor_id},
        socket
      ) do
    WasmcloudHost.ActorWatcher.stop_hotwatch(:actor_watcher, actor_id)
    {:noreply, assign(socket, is_hotwatched: false)}
  end

  def render(assigns) do
    ~L"""
    <tr>
      <td>
        <%= @name %>
      </td>
      <td><%= @count %></td>
      <td>
        <span class="badge <%= case @status do
              "Awaiting" -> "badge-secondary"
              "Healthy" -> "badge-success"
              "Unhealthy" -> "badge-danger"
              end%>">
          <%= @status %></span>
        <%= if @is_hotwatched do %>
          <span class="badge badge-danger">Hot reloading</span>
        <% end %>
      </td>
      <td>
        <button id="copy_actor_id_<%= @actor %>_<%= @host_id %>" class="btn btn-sm btn-primary" data-toggle="tooltip"
          data-placement="top" title data-original-title="Copy Actor ID"
          onClick="navigator.clipboard.writeText('<%= @actor %>')">
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button>
        <button id="copy_host_id_<%= @actor%>_<%= @host_id %>" class="btn btn-sm btn-info" data-toggle="tooltip"
          data-placement="top" onClick="navigator.clipboard.writeText('<%= @host_id %>')" title
          data-original-title="Copy Host ID">
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button>
        <button id="scale_actor_button_<%= @actor %>_<%= @host_id %>" class="btn btn-sm btn-warning" data-toggle="tooltip"
          data-placement="top" title data-original-title="Scale Actor" phx-click="show_modal"
          phx-value-title='Scale "<%= @name %>"' phx-value-component="ScaleActorComponent" phx-value-id="scale_actor_modal"
          phx-value-actor="<%= @actor %>" phx-value-host="<%= @host_id %>" phx-value-replicas="<%= @count %>"
          phx-value-oci="<%= @oci_ref %>">
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-equalizer"></use>
          </svg>
        </button>
        <%= if @is_hotwatched do %>
        <button id="stop_hotwatch_button_<%= @actor %>_<%= @host_id %>" class="btn btn-sm btn-danger" data-toggle="tooltip"
          data-placement="top" title data-original-title="Stop Hotwatch" phx-target="<%= @myself %>"
          phx-click="stop_hotwatch" phx-value-actor_id="<%= @actor %>">
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-fire"></use>
          </svg>
        </button>
        <% end %>
        <script>
          createTooltip(document.getElementById("scale_actor_button_<%= @actor %>_<%= @host_id %>"))
          createTooltip(document.getElementById("copy_actor_id_<%= @actor %>_<%= @host_id %>"))
          createTooltip(document.getElementById("copy_host_id_<%= @actor %>_<%= @host_id %>"))
          createTooltip(document.getElementById("stop_hotwatch_button_<%= @actor %>_<%= @host_id %>"))
        </script>
      </td>
    </tr>
    """
  end
end
