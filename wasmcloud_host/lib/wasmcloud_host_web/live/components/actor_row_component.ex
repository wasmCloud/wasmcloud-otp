defmodule ActorRowComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~L"""
    <tr>
      <%= for {k, v} <- @claims do %>
        <%= if k == @actor do %>
          <td><%= v.name %> </td>
        <% end %>
      <% end %>
      <td><%= @count %></td>
      <td>
        <span class="badge <%= case @status do
          "Starting" -> "badge-secondary"
          "Healthy" -> "badge-success"
          "Unhealthy" -> "badge-danger"
          end%>">
          <%= @status %></span>
      </td>
      <td>
        <button class="btn btn-primary btn-sm" type="button" onClick="navigator.clipboard.writeText('<%= @actor %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
          <%= String.slice(@actor, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>&nbsp;
        </button>
      </td>
      <td>
        <button class="btn btn-primary btn-sm" type="button" onClick="navigator.clipboard.writeText('<%= @host_id %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
          <%= String.slice(@host_id, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>&nbsp;
        </button>
      </td>
    </tr>
    """
  end
end
