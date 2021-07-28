defmodule StartProviderComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok,
     socket
     |> assign(:uploads, %{})
     # TODO: Only allow parJEEzys
     |> allow_upload(:provider, accept: :any, max_entries: 1)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "start_provider_file",
        %{
          "provider_key" => provider_key,
          "provider_link_name" => provider_link_name,
          "provider_contract_id" => provider_contract_id
        },
        socket
      ) do
    Phoenix.LiveView.consume_uploaded_entries(socket, :provider, fn %{path: path}, _entry ->
      {:ok, bytes} = File.read(path)
      dir = System.tmp_dir!()
      tmp_file = Path.join(dir, Path.basename(path))
      File.write!(tmp_file, bytes)
      File.chmod(tmp_file, 0o755)

      case HostCore.Providers.ProviderSupervisor.start_executable_provider(
             tmp_file,
             provider_key,
             provider_link_name,
             provider_contract_id
           ) do
        {:ok, _pid} -> :ok
        {:error, _reason} -> :error
      end
    end)

    {:noreply, socket}
  end

  def handle_event(
        "start_provider_ociref",
        %{
          "provider_ociref" => provider_ociref,
          "provider_link_name" => provider_link_name
        },
        socket
      ) do
    case HostCore.Providers.ProviderSupervisor.start_executable_provider_from_oci(
           provider_ociref,
           provider_link_name
         ) do
      {:ok, _pid} -> :ok
      {:error, _reason} -> :error
      {:stop, _reason} -> :error
    end

    {:noreply, socket}
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
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Public Key</label>
        <div class="col-md-9">
          <input class="form-control" id="text-input" type="text" name="provider_key" placeholder="VABCD...">
          <span class="help-block">56 character provider public key (starts with "V")</span>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Contract ID</label>
        <div class="col-md-9">
          <input class="form-control" id="text-input" type="text" name="provider_contract_id" placeholder="wasmcloud:contract">
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
          <input class="form-control" id="text-input" type="text" name="provider_link_name" placeholder="default" value="default">
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn btn-secondary" type="button" phx-click="hide_modal">Close</button>
        <button class="btn btn-primary" type="submit" phx-click="hide_modal">Submit</button>
      </div>
    </form>
    """
  end
end
