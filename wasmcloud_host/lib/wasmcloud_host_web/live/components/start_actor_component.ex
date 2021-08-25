defmodule StartActorComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok,
     socket
     |> assign(:uploads, %{})
     |> assign(:error_msg, nil)
     |> allow_upload(:actor, accept: ~w(.wasm), max_entries: 1)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "start_actor_file",
        %{"replicas" => replicas},
        socket
      ) do
    error_msg =
      Phoenix.LiveView.consume_uploaded_entries(socket, :actor, fn %{path: path}, _entry ->
        replicas = 1..String.to_integer(replicas)

        case File.read(path) do
          {:ok, bytes} ->
            replicas
            |> Enum.reduce_while("", fn _, _ ->
              case HostCore.Actors.ActorSupervisor.start_actor(bytes) do
                {:stop, err} ->
                  {:halt, "Error: #{err}"}

                _any ->
                  {:cont, ""}
              end
            end)

          {:error, reason} ->
            "Error #{reason}"
        end
      end)
      |> List.first()

    case error_msg do
      nil ->
        {:noreply, assign(socket, error_msg: "Please select a file")}

      "" ->
        Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
        {:noreply, assign(socket, error_msg: nil)}

      msg ->
        {:noreply, assign(socket, error_msg: msg)}
    end
  end

  def handle_event(
        "start_actor_ociref",
        %{"replicas" => replicas, "actor_ociref" => actor_ociref, "host_id" => host_id},
        socket
      ) do
    case host_id do
      "" ->
        case WasmcloudHost.Lattice.ControlInterface.auction_actor(actor_ociref, %{}) do
          {:ok, auction_host_id} ->
            start_actor(actor_ociref, replicas, auction_host_id, socket)

          {:error, error} ->
            {:noreply, assign(socket, error_msg: error)}
        end

      host_id ->
        start_actor(actor_ociref, replicas, host_id, socket)
    end
  end

  defp start_actor(actor_ociref, replicas, host_id, socket) do
    case WasmcloudHost.Lattice.ControlInterface.start_actor(actor_ociref, replicas, host_id) do
      :ok ->
        Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
        {:noreply, assign(socket, error_msg: nil)}

      {:error, error} ->
        {:noreply, assign(socket, error_msg: error)}
    end
  end

  def render(assigns) do
    modal_id =
      if assigns.id == :start_actor_file_modal do
        "start_actor_file"
      else
        "start_actor_ociref"
      end

    ~L"""
    <form class="form-horizontal" phx-submit="<%= modal_id %>" phx-change="validate" phx-target="<%= @myself %>">
      <input name="_csrf_token" type="hidden" value="<%= Phoenix.Controller.get_csrf_token() %>">
      <%= if assigns.id == :start_actor_file_modal do %>
      <div class="form-group row" phx-drop-target="<%= @uploads.actor.ref %>">
        <label class="col-md-3 col-form-label" for="file-input">File</label>
        <div class="col-md-9">
          <%= live_file_input @uploads.actor %>
        </div>
      </div>
      <% else %>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Desired Host</label>
        <div class="col-md-9">
          <%# On select, populate the linkname and contract_id options with the matching data %>
          <select class="form-control select2-single id-monospace" id="host-id-select" name="host_id">
            <%= if @selected_host != nil do %>
              <option value> -- First available -- </option>
              <%= for {host_id, _host_map} <- @hosts do %>
                <%= if host_id == @selected_host do %>
                  <option selected value="<%= host_id %>"
                    data-host-id="<%= host_id %>">
                    <%= String.slice(host_id, 0..4) %>...
                  </option>
                <% else %>
                  <option value="<%= host_id %>"
                    data-host-id="<%= host_id %>">
                    <%= String.slice(host_id, 0..4) %>...
                  </option>
                <% end %>
              <% end %>
            <% else %>
              <option selected value> -- First available -- </option>
              <%= for {host_id, _host_map} <- @hosts do %>
                <option value="<%= host_id %>"
                  data-host-id="<%= host_id %>">
                  <%= String.slice(host_id, 0..4) %>...
                </option>
              <% end %>
            <% end %>
          </select>
          <span class="help-block"><strong>First available</strong> will hold an auction for an appropriate host</span>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="file-input">OCI reference</label>
        <div class="col-md-9">
          <input class="form-control" id="text-input" type="text" name="actor_ociref" placeholder="wasmcloud.azurecr.io/echo:0.2.0" value="" required>
          <span class="help-block">Enter an OCI reference</span>
        </div>
      </div>
      <% end %>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Replicas</label>
        <div class="col-md-9">
          <input class="form-control" id="number-input" type="number" name="replicas" placeholder="1" value="1" min="1">
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
