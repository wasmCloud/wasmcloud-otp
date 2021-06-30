defmodule DefineLinkComponent do
  use Phoenix.LiveComponent

  def mount(socket) do
    {:ok, socket}
  end

  def handle_event("validate", _params, socket) do
    # TODO determine feasability of modifying form upon provider select, instead of with custom JS
    {:noreply, socket}
  end

  def handle_event(
        "define_link",
        %{
          "actor_id" => actor_id,
          "contract_id" => contract_id,
          "link_name" => link_name,
          "provider_id" => provider_id,
          "values" => values
        },
        socket
      ) do
    values_map =
      values
      |> String.split(",")
      |> Enum.flat_map(fn s -> String.split(s, "=") end)
      |> Enum.chunk_every(2)
      |> Enum.map(fn [a, b] -> {a, b} end)
      |> Map.new()

    HostCore.Linkdefs.Manager.put_link_definition(
      actor_id,
      contract_id,
      link_name,
      provider_id,
      values_map
    )

    {:noreply, socket}
  end

  def render(assigns) do
    ~L"""
    <form class="form-horizontal" phx-submit="define_link" phx-change="validate" phx-target="<%= @myself %>">
      <input name="_csrf_token" type="hidden" value="<%= Phoenix.Controller.get_csrf_token() %>">
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Actor Public Key</label>
        <div class="col-md-9">
          <select class="form-control select2-single" id="select2-1" name="actor_id">
            <option hidden disabled selected value> -- select an actor -- </option>
            <%= for {actor, _host_map} <- @actors do %>
              <%= for {k, v} <- @claims do %>
                <%= if k == actor do %>
                  <option value="<%= actor %>"><%= v.name %> (<%= String.slice(actor, 0..4) %>...) </option>
                <% end %>
              <% end %>
            <% end %>
          </select>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="text-input">Provider Public Key</label>
        <div class="col-md-9">
          <%# On select, populate the linkname and contract_id options with the matching data %>
          <select class="form-control select2-single" id="linkdefs-providerid-select" name="provider_id"
          onChange="let data = this.options[this.selectedIndex].dataset
            document.getElementById('linkdef-linkname-input').value = data['linkname']
            document.getElementById('linkdef-contractid-input').value = data['contractid']">
            <option hidden disabled selected value> -- select a provider -- </option>
            <%= for {provider, instances} <- @providers do %>
              <%= for instance <- instances do  %>
                <option value="<%= provider %>"
                  data-linkname="<%= Map.get(instance, :link_name)%>"
                  data-contractid="<%= Map.get(instance, :contract_id)%>">
                  <%= String.slice(provider, 0..4) %>... (<%= Map.get(instance, :link_name) %>)
                </option>
              <% end %>
            <% end %>
          </select>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="linkdef-linkname-input">Link Name</label>
        <div class="col-md-9">
          <input class="form-control" id="linkdef-linkname-input" type="text" name="link_name" placeholder="default" value="default">
          <span class="help-block">Select a provider to autopopulate the link name</span>
        </div>
      </div>
      <div class="form-group row">
        <label class="col-md-3 col-form-label" for="linkdef-contractid-input">Contract ID</label>
        <div class="col-md-9">
          <input class="form-control" id="linkdef-contractid-input" type="text" name="contract_id" placeholder="wasmcloud:contract">
          <span class="help-block">Select a provider to autopopulate the contract id</span>
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
        <button id="close_modal-<%= @id %>" class="btn btn-secondary" type="button" data-dismiss="modal">Close</button>
        <!-- onClick event closes modal -->
        <button class="btn btn-primary" type="submit" onClick="document.getElementById('close_modal-<%= @id %>').click()">Submit</button>
      </div>
    </form>
    """
  end
end
