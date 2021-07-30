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
        %{"replicas" => replicas, "actor_ociref" => actor_ociref},
        socket
      ) do
    replicas = 1..String.to_integer(replicas)

    error_msg =
      replicas
      |> Enum.reduce_while("", fn _, _ ->
        case HostCore.Actors.ActorSupervisor.start_actor_from_oci(actor_ociref) do
          {:stop, err} ->
            {:halt, "Error: #{err}"}

          _any ->
            {:cont, ""}
        end
      end)

    if error_msg != "" do
      {:noreply, assign(socket, error_msg: error_msg)}
    else
      Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
      {:noreply, assign(socket, error_msg: nil)}
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
        <button class="btn btn-primary" type="submit" >Submit</button>
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
