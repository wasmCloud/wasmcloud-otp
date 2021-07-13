defmodule WasmcloudHost.Lattice.StateMonitor do
  use GenServer, restart: :transient
  alias Phoenix.PubSub

  require Logger

  # TODO - reconcile the fact that linkdefs and claims are being stored in th is
  # map AND in ETS storage under their respective manager processes.

  defmodule State do
    defstruct [:actors, :providers, :linkdefs, :refmaps, :claims]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :state_monitor)
  end

  @impl true
  def init(_opts) do
    state = %State{actors: %{}, providers: %{}, linkdefs: %{}, refmaps: %{}, claims: %{}}
    prefix = HostCore.Host.lattice_prefix()

    topic = "wasmbus.evt.#{prefix}"
    {:ok, _sub} = Gnat.sub(:control_nats, self(), topic)

    ldtopic = "wasmbus.rpc.#{prefix}.*.*.linkdefs.*"
    {:ok, _sub} = Gnat.sub(:lattice_nats, self(), ldtopic)

    claimstopic = "wasmbus.rpc.#{prefix}.claims.put"
    {:ok, _sub} = Gnat.sub(:lattice_nats, self(), claimstopic)

    {:ok, state}
  end

  @impl true
  def handle_call(:actor_query, _from, state) do
    {:reply, state.actors, state}
  end

  @impl true
  def handle_call(:provider_query, _from, state) do
    {:reply, state.providers, state}
  end

  @impl true
  def handle_call(:linkdef_query, _from, state) do
    {:reply, state.linkdefs, state}
  end

  @impl true
  def handle_call(:claims_query, _from, state) do
    {:reply, state.claims, state}
  end

  @impl true
  def handle_info(
        {:msg, %{body: body, topic: topic}},
        state
      ) do
    Logger.info("StateMonitor handle info #{topic}")

    state =
      cond do
        String.starts_with?(topic, "wasmbus.evt.") ->
          handle_event(state, body)

        String.contains?(topic, ".linkdefs.") ->
          handle_linkdef(state, body, topic)

        String.contains?(topic, ".claims.") ->
          handle_claims(state, body, topic)
      end

    {:noreply, state}
  end

  def get_actors() do
    GenServer.call(:state_monitor, :actor_query)
  end

  def get_providers() do
    GenServer.call(:state_monitor, :provider_query)
  end

  def get_linkdefs() do
    GenServer.call(:state_monitor, :linkdef_query)
  end

  def get_claims() do
    GenServer.call(:state_monitor, :claims_query)
  end

  defp handle_linkdef(state, body, topic) do
    Logger.info("Handling linkdef state update")
    cmd = topic |> String.split(".") |> Enum.at(6)
    ld = Msgpax.unpack!(body)
    key = {ld["actor_id"], ld["contract_id"], ld["link_name"]}
    map = %{values: ld["values"], provider_key: ld["provider_id"]}

    linkdefs =
      if cmd == "put" do
        Map.put(state.linkdefs, key, map)
      else
        Map.delete(state.linkdefs, key)
      end

    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:linkdefs, linkdefs})
    %State{state | linkdefs: linkdefs}
  end

  defp handle_claims(state, body, topic) do
    Logger.info("Handling claims state")
    cmd = topic |> String.split(".") |> Enum.at(4)
    claims = Msgpax.unpack!(body) |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    cmap =
      if cmd == "put" do
        Map.put(state.claims, claims.sub, claims)
      else
        Map.delete(state.claims, claims.sub)
      end

    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:claims, cmap})
    %State{state | claims: cmap}
  end

  defp handle_event(state, body) do
    evt =
      body
      |> Cloudevents.from_json!()

    process_event(state, evt)
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{
             "public_key" => pk
           },
           source: source_host,
           datacontenttype: "application/json",
           type: "com.wasmcloud.lattice.actor_started"
         }
       ) do
    actors = add_actor(pk, source_host, state.actors)
    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:actors, actors})
    %State{state | actors: actors}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"public_key" => public_key, "running_instances" => remaining_count},
           datacontenttype: "application/json",
           source: source_host,
           type: "com.wasmcloud.lattice.actor_stopped"
         }
       ) do
    actors = set_actor_count(public_key, source_host, remaining_count, state.actors)
    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:actors, actors})
    %State{state | actors: actors}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{
             "public_key" => pk,
             "link_name" => link_name,
             "contract_id" => contract_id
           },
           source: source_host,
           datacontenttype: "application/json",
           type: "com.wasmcloud.lattice.provider_started"
         }
       ) do
    providers = add_provider(pk, link_name, contract_id, source_host, state.providers)
    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:providers, providers})
    %State{state | providers: providers}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"link_name" => _link_name, "public_key" => _pk},
           datacontenttype: "application/json",
           source: _source_host,
           type: "com.wasmcloud.lattice.provider_stopped"
         }
       ) do
    providers = state.providers
    # TODO - remove provider from list

    %State{state | providers: providers}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"actors" => _actors, "providers" => _providers},
           datacontenttype: "application/json",
           source: _source_host,
           type: "com.wasmcloud.lattice.host_heartbeat"
         }
       ) do
    Logger.info("Handling host heartbeat")
    # TODO: handle heartbeats
    state
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"public_key" => public_key},
           datacontenttype: "application/json",
           source: source_host,
           type: "com.wasmcloud.lattice.health_check_passed"
         }
       ) do
    Logger.info("Handling successful health check for #{public_key}")
    update_status(state, public_key, source_host, "Healthy")
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"public_key" => public_key},
           datacontenttype: "application/json",
           source: source_host,
           type: "com.wasmcloud.lattice.health_check_failed"
         }
       ) do
    Logger.info("Handling failed health check for #{public_key}")
    update_status(state, public_key, source_host, "Unhealthy")
  end

  defp update_status(state, public_key, source_host, new_status) do
    actors = state.actors
    providers = state.providers
    actor = Map.get(actors, public_key, nil)
    provider_list = Map.get(providers, public_key, nil)

    cond do
      actor != nil ->
        host_map = Map.get(actor, source_host, %{})
        host_map = Map.put(host_map, :status, new_status)
        actor = Map.put(actor, source_host, host_map)
        actors = Map.put(actors, public_key, actor)
        PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:actors, actors})
        %State{state | actors: actors}

      provider_list != nil ->
        provider_list =
          provider_list
          |> Enum.map(
            fn instance = %{
                 link_name: link_name,
                 contract_id: contract_id,
                 host_ids: host_ids,
                 status: _status
               } ->
              if Enum.member?(host_ids, source_host) do
                %{
                  link_name: link_name,
                  contract_id: contract_id,
                  host_ids: host_ids,
                  status: new_status
                }
              else
                instance
              end
            end
          )

        providers = Map.put(providers, public_key, provider_list)
        PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:providers, providers})
        %State{state | providers: providers}

      # Did not match currently running provider or actor
      true ->
        state
    end
  end

  # This map is keyed by provider public key, which contains a list of
  # maps with the keys "link_name", "contract_id", and "host_ids", as
  # shown below.
  #
  # %{
  #     "Vxxxx":  [
  #        %{
  #            "link_name": "default",
  #            "contract_id": "wasmcloud:keyvalue",
  #            "host_ids": ["Nxxxx"],
  #            "status": "Starting"
  #         },
  #        %{
  #            "link_name": "special",
  #            "contract_id": "wasmcloud:keyvalue",
  #            "host_ids": ["Nxxxx"],
  #            "status": "Healthy"
  #         },
  #    ]
  # }
  def add_provider(pk, link_name, contract_id, host, previous_map) do
    # This logic will add in a new entry for every call
    # It shouldn't add information if it's a duplicate, and it should only
    # append a host_id to the list if the link_name + contract_id already exists
    previous_instances = Map.get(previous_map, pk, [])

    # Check for existence of link_name and contract_id pair
    existing_instance =
      previous_instances
      |> Enum.filter(fn info ->
        Map.get(info, :link_name) == link_name && Map.get(info, :contract_id) == contract_id
      end)
      |> List.first()

    cond do
      # new instance of provider, add to provider list
      existing_instance == nil ->
        provider_list = [
          %{link_name: link_name, contract_id: contract_id, host_ids: [host], status: "Starting"}
          | previous_instances
        ]

        Map.put(previous_map, pk, provider_list)

      # provider is already running with the same link and contract id on this host
      # This condition shouldn't be reached, as this attempt should be stopped at the host level
      existing_instance != nil &&
          existing_instance
          |> Map.get(:host_ids)
          |> Enum.any?(fn id -> id == host end) ->
        {:error, "Provider instance already exists"}

      # provider with this contract_id and link_name is not running on this host, append new host
      true ->
        Map.put(existing_instance, :host_ids, [host | Map.get(existing_instance, :host_ids)])
    end
  end

  # This map is keyed with the actor public key and holds a map
  # containing a host ID mapping to the status of the actor on that
  # host and a total count on that host
  #
  # %{
  #   "Mxxxx" : %{
  #     "Nxxxxx": %{
  #       "status": "Healthy"/"Unhealthy"/"Starting",
  #       "count": 3
  #     },
  #     "Nxxxxy": %{
  #       "status": "Healthy"/"Unhealthy"/"Starting",
  #       "count": 3
  #     },
  #   }
  # }
  def add_actor(pk, host, previous_map) do
    actor_map = Map.get(previous_map, pk, %{})
    host_map = Map.get(actor_map, host, %{})
    new_count = Map.get(host_map, :count, 0) + 1
    host_map = Map.put(host_map, :count, new_count)
    host_map = Map.put(host_map, :status, "Starting")

    actor_map = Map.put(actor_map, host, host_map)
    Map.put(previous_map, pk, actor_map)
  end

  defp set_actor_count(pk, host, count, previous_map) do
    actor_map = Map.get(previous_map, pk, %{})
    actor_map = Map.put(actor_map, host, count)
    Map.put(previous_map, pk, actor_map)
  end
end
