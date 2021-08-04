defmodule ScaleActorComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok,
     socket
     |> assign(:error_msg, nil)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "scale_actor",
        params,
        socket
      ) do
    current = socket.replicas
    desired = String.to_integer(params.replicas)

    # case error_msg do
    #   nil ->
    #     {:noreply, assign(socket, error_msg: "Please select a file")}

    #   "" ->
    #     Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
    #     {:noreply, assign(socket, error_msg: nil)}

    #   msg ->
    #     {:noreply, assign(socket, error_msg: msg)}
    # end
    {:noreply, socket}
  end

  def render(assigns) do
    replicas = 1

    ~L"""
    <form class="form-horizontal" phx-submit="scale_actor" phx-change="validate" phx-target="<%= @myself %>">
      <input name="_csrf_token" type="hidden" value="<%= Phoenix.Controller.get_csrf_token() %>">
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Replicas</label>
        <div class="col-md-9">
          <input class="form-control" id="number-input" type="number" name="replicas" value="<%= replicas %>" min="0">
          <span class="help-block">Enter how many instances of this actor you want</span>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn btn-secondary" type="button" phx-click="hide_modal">Close</button>
        <button class="btn btn-primary" type="submit">Submit</button>
      </div>
    </form>
    <%= if @error_msg != nil do %>
    <div class="alert alert-danger">
    <%= @error_msg %>
    </div>
    <% end %>
    """
  end
end
