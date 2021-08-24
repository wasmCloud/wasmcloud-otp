defmodule ActorRowComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~L"""
    <tr>
      <td><%= @name %> </td>
      <td><%= @count %></td>
      <td>
        <span class="badge <%= case @status do
          "Awaiting" -> "badge-secondary"
          "Healthy" -> "badge-success"
          "Unhealthy" -> "badge-danger"
          end%>">
          <%= @status %></span>
      </td>
      <td>
        <button class="btn btn-primary btn-sm id-monospace" type="button" onClick="navigator.clipboard.writeText('<%= @actor %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
          <%= String.slice(@actor, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button>
      </td>
      <td>
        <button class="btn btn-primary btn-sm id-monospace" type="button" onClick="navigator.clipboard.writeText('<%= @host_id %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
          <%= String.slice(@host_id, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button>
      </td>
      <td>
        <button class="btn btn-sm btn-warning"
          data-toggle="tooltip"
          data-placement="top"
          title data-original-title="Scale Actor"
          phx-click="show_modal"
          phx-value-title='Scale "<%= @name %>"'
          phx-value-component="ScaleActorComponent"
          phx-value-id="scale_actor_modal"
          phx-value-actor="<%= @actor %>"
          phx-value-host="<%= @host_id %>"
          phx-value-replicas="<%= @count %>">
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-equalizer"></use>
          </svg>
        </button>
      </td>
      </tr>
    """
  end
end
