defmodule LinkRowComponent do
  use Phoenix.LiveComponent

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
    </tr>
    """
  end
end
