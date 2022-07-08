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
          "provider_link_name" => provider_link_name,
          "host_id" => host_id
        },
        socket
      ) do
    case host_id do
      "" ->
        case WasmcloudHost.Lattice.ControlInterface.auction_provider(
               provider_ociref,
               provider_link_name,
               %{}
             ) do
          {:ok, auction_host_id} ->
            start_provider(provider_ociref, provider_link_name, auction_host_id, socket)

          {:error, error} ->
            {:noreply, assign(socket, error_msg: error)}
        end

      host_id ->
        start_provider(provider_ociref, provider_link_name, host_id, socket)
    end
  end

  defp start_provider(provider_ociref, provider_link_name, host_id, socket) do
    case WasmcloudHost.Lattice.ControlInterface.start_provider(
           provider_ociref,
           provider_link_name,
           host_id
         ) do
      :ok ->
        Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
        {:noreply, assign(socket, error_msg: nil)}

      {:error, error} ->
        {:noreply, assign(socket, error_msg: error)}
    end
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
        <label class="col-md-3 col-form-label" for="text-input">Desired Host</label>
        <div class="col-md-9">
          <%# On select, populate the linkname and contract_id options with the matching data %>
          <select class="form-control select2-single id-monospace" id="host-id-select" name="host_id">
            <%= if @selected_host != nil do %>
            <option value> -- First available -- </option>
            <%= for {host_id, _host_map} <- @hosts do %>
            <%= if host_id == @selected_host do %>
            <option selected value="<%= host_id %>" data-host-id="<%= host_id %>">
              <%= String.slice(host_id, 0..4) %>...
            </option>
            <% else %>
            <option value="<%= host_id %>" data-host-id="<%= host_id %>">
              <%= String.slice(host_id, 0..4) %>...
            </option>
            <% end %>
            <% end %>
            <% else %>
            <option selected value> -- First available -- </option>
            <%= for {host_id, _host_map} <- @hosts do %>
            <option value="<%= host_id %>" data-host-id="<%= host_id %>">
              <%= String.slice(host_id, 0..4) %>...
            </option>
            <% end %>
            <% end %>
          </select>
          <span class="help-block"><strong>First available</strong> will hold an auction for an appropriate host</span>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="file-input">OCI Reference</label>
        <div class="col-md-9">
          <input class="form-control" id="provider-ociref-input" type="text" name="provider_ociref"
            placeholder="wasmcloud.azurecr.io/httpserver:0.16.0" value="" required>
          <span class="help-block">Enter an OCI reference</span>
        </div>
      </div>
      <% end %>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Link Name</label>
        <div class="col-md-9">
          <input class="form-control" id="text-input" type="text" name="provider_link_name" placeholder="default"
            value="default" required>
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
