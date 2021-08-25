defmodule DefineLinkComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, socket |> assign(:error_msg, nil)}
  end

  def handle_event("validate", _params, socket) do
    # TODO determine feasability of modifying form upon provider select, instead of with custom JS
    {:noreply, socket}
  end

  def handle_event(
        "define_link",
        linkdef,
        socket
      ) do
    actor_id = Map.get(linkdef, "actor_id")
    provider_id = Map.get(linkdef, "provider_id")
    contract_id = Map.get(linkdef, "contract_id")
    link_name = Map.get(linkdef, "link_name")
    values = Map.get(linkdef, "values")

    values_map =
      case values do
        "" ->
          Map.new()

        nil ->
          Map.new()

        value_list ->
          value_list
          |> String.split(",")
          |> Enum.flat_map(fn s -> String.split(s, "=") end)
          |> Enum.chunk_every(2)
          |> Enum.map(fn [a, b] -> {a, b} end)
          |> Map.new()
      end

    error_msg =
      cond do
        actor_id == nil ->
          "Please select an Actor ID to link"

        provider_id == nil ->
          "Please select a Provider ID to link"

        true ->
          case HostCore.Linkdefs.Manager.put_link_definition(
                 actor_id,
                 contract_id,
                 link_name,
                 provider_id,
                 values_map
               ) do
            :ok -> nil
            _any -> "Error publishing link definition"
          end
      end

    if error_msg == nil do
      Phoenix.PubSub.broadcast(WasmcloudHost.PubSub, "frontend", :hide_modal)
    end

    {:noreply, assign(socket, error_msg: error_msg)}
  end

  def render(assigns) do
    ~L"""
    <form class="form-horizontal" phx-submit="define_link" phx-change="validate" phx-target="<%= @myself %>">
      <input name="_csrf_token" type="hidden" value="<%= Phoenix.Controller.get_csrf_token() %>">
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Actor</label>
        <div class="col-md-9">
          <select class="form-control select2-single" id="select2-1" name="actor_id">
            <option hidden disabled selected value> -- select an actor -- </option>
            <%= for {k, v} <- @claims do %>
            <%= if String.starts_with?(k, "M") && String.length(k) == 56 do %>
            <option value="<%= k %>"><%= v.name %> (<%= String.slice(k, 0..4) %>...) </option>
            <% end %>
            <% end %>
          </select>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Provider</label>
        <div class="col-md-9">
          <%# On select, populate the linkname and contract_id options with the matching data %>
          <select class="form-control select2-single" id="linkdefs-providerid-select" name="provider_id">
            <option hidden disabled selected value> -- select a provider -- </option>
            <%= for {k, v} <- @claims do %>
            <%= if String.starts_with?(k, "V") && String.length(k) == 56 do %>
            <option value="<%= k %>"><%= v.name %> (<%= String.slice(k, 0..4) %>...) </option>
            <% end %>
            <% end %>
          </select>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="linkdef-linkname-input">Link Name</label>
        <div class="col-md-9">
          <input class="form-control" id="linkdef-linkname-input" type="text" name="link_name" placeholder="default"
            value="default" required>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="linkdef-contractid-input">Contract ID</label>
        <div class="col-md-9">
          <input class="form-control" id="linkdef-contractid-input" type="text" name="contract_id"
            placeholder="wasmcloud:contract" required>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Values</label>
        <div class="col-md-9">
          <input class="form-control" id="text-input" type="text" name="values" placeholder="KEY1=VAL1,KEY2=VAL2">
          <span class="help-block">Comma separated list of configuration values</span>
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
