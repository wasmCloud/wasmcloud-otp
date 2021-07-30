defmodule StartProviderComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok,
     socket
     |> assign(:uploads, %{})
     |> assign(:error_msg, nil)
     |> allow_upload(:provider, accept: ~w(.par .gz), max_entries: 1, max_file_size: 64_000_000)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "start_provider_file",
        %{
          "provider_link_name" => provider_link_name
        },
        socket
      ) do
    error_msg =
      Phoenix.LiveView.consume_uploaded_entries(socket, :provider, fn %{path: path}, _entry ->
        case HostCore.Providers.ProviderSupervisor.start_provider_from_file(
               path,
               provider_link_name
             ) do
          {:ok, _pid} -> ""
          {:error, reason} -> reason
        end
      end)
      |> List.first()

    case error_msg do
      nil ->
        {:noreply, assign(socket, error_msg: "Please select a provider archive file")}

      "" ->
        Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
        {:noreply, assign(socket, error_msg: nil)}

      msg ->
        {:noreply, assign(socket, error_msg: msg)}
    end
  end

  def handle_event(
        "start_provider_ociref",
        %{
          "provider_ociref" => provider_ociref,
          "provider_link_name" => provider_link_name
        },
        socket
      ) do
    error_msg =
      case HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
             provider_ociref,
             provider_link_name
           ) do
        {:ok, _pid} -> nil
        {:error, reason} -> reason
        {:stop, reason} -> reason
      end

    if error_msg == nil do
      Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
    end

    {:noreply, assign(socket, error_msg: error_msg)}
  end

  def render(assigns) do
    submit_action =
      if assigns.id == :start_provider_file_modal do
        "start_provider_file"
      else
        "start_provider_ociref"
      end

    ~L"""
    <form class="form-horizontal" phx-submit="<%= submit_action %>" phx-change="validate" phx-target="<%= @myself %>">
      <input name="_csrf_token" type="hidden" value="<%= Phoenix.Controller.get_csrf_token() %>">
      <%= if assigns.id == :start_provider_file_modal do %>
      <div class="form-group row" phx-drop-target="<%= @uploads.provider.ref %>">
        <label class="col-md-3 col-form-label" for="file-input">File</label>
        <div class="col-md-9">
          <%= live_file_input @uploads.provider %>
        </div>
      </div>
      <% else %>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="file-input">OCI Reference</label>
        <div class="col-md-9">
          <input class="form-control" id="provider-ociref-input" type="text" name="provider_ociref" placeholder="wasmcloud.azurecr.io/httpserver:0.12.1" value="">
          <span class="help-block">Enter an OCI reference</span>
        </div>
      </div>
      <% end %>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Link Name</label>
        <div class="col-md-9">
          <input class="form-control" id="text-input" type="text" name="provider_link_name" placeholder="default" value="default" required>
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
