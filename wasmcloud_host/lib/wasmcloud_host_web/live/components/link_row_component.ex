defmodule LinkRowComponent do
  use Phoenix.LiveComponent

  def handle_event(
        "delete_linkdef",
        %{"actor_id" => actor_id, "contract_id" => contract_id, "link_name" => link_name},
        socket
      ) do
    WasmcloudHost.Lattice.ControlInterface.delete_linkdef(actor_id, contract_id, link_name)
    {:noreply, socket}
  end

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~L"""
    <tr>
      <td><%= @link_name %></td>
      <td><%= @contract_id %></td>
      <td><button class="btn btn-primary btn-sm id-monospace" type="button"
          onClick="navigator.clipboard.writeText('<%= @actor_id %>')" data-toggle="popover" data-trigger="focus" title=""
          data-content="Copied!">
          <%= String.slice(@actor_id, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button></td>
      <td>
        <button class="btn btn-primary btn-sm id-monospace" type="button"
          onClick="navigator.clipboard.writeText('<%= @provider_key %>')" data-toggle="popover" data-trigger="focus"
          title="" data-content="Copied!">
          <%= String.slice(@provider_key, 0..4) %>...
          <svg class="c-icon">
            <use xlink:href="/coreui/free.svg#cil-copy"></use>
          </svg>
        </button>
      </td>
      <td>

    <button class="btn btn-sm btn-danger" id="delete_linkdef_<%= @actor_id %>_<%= @link_name %>_<%= @contract_id %>"
    data-toggle="tooltip" data-placement="top" title data-original-title="Delete Linkdef" phx-target="<%= @myself %>"
    phx-click="delete_linkdef" phx-value-contract_id="<%= @contract_id %>" phx-value-link_name="<%= @link_name %>"
    phx-value-actor_id="<%= @actor_id %>">
          <svg class="c-icon" style="color: white">
            <use xlink:href="/coreui/free.svg#cil-trash"></use>
          </svg>
        </button>
      </td>
    </tr>
    """
  end
end
