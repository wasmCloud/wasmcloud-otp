defmodule ProviderRowComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~L"""
    <tr>
      <td><%= @link_name %></td>
      <td><%= @contract_id %></td>
      <td>
        <span class="badge <%= case @status do
            "Starting" -> "badge-secondary"
            "Healthy" -> "badge-success"
            "Unhealthy" -> "badge-danger"
            end%>">
          <%= @status %></span>
      </td>
      <td><button class="btn btn-primary btn-sm" type="button" onClick="navigator.clipboard.writeText('<%= @provider %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
          <%= String.slice(@provider, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>&nbsp;
        </button></td>
      <td>
        <%= for hid <- @host_ids do %>
          <button class="btn btn-primary btn-sm" type="button" onClick="navigator.clipboard.writeText('<%= hid %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
            <%= String.slice(hid, 0..4) %>...
            <svg class="c-icon">
              <use xlink:href="/coreui/free.svg#cil-copy"></use>
            </svg>&nbsp;
          </button>
        <% end %>
      </td>
    </tr>
    """
  end
end
