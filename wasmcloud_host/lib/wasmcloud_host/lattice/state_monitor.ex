defmodule WasmcloudHost.Lattice.StateMonitor do
  use GenServer, restart: :transient
  alias Phoenix.PubSub

  require Logger

  # TODO - reconcile the fact that linkdefs and claims are being stored in th is
  # map AND in ETS storage under their respective manager processes.

  defmodule State do
    defstruct [:actors, :providers, :linkdefs, :refmaps, :claims, :hosts]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: :state_monitor)
  end

  @impl true
  def init(_opts) do
    state = %State{
      actors: %{},
      providers: %{},
      linkdefs: %{},
      refmaps: %{},
      claims: %{},
      hosts: %{
        HostCore.Host.host_key() => %{
          actors: %{},
          providers: %{},
          labels: HostCore.Host.host_labels()
        }
      }
    }

    prefix = HostCore.Host.lattice_prefix()

    topic = "wasmbus.evt.#{prefix}"
    {:ok, _sub} = Gnat.sub(:control_nats, self(), topic)

    Registry.register(Registry.EventMonitorRegistry, "cache_loader_events", [])

    {:ok, state, {:continue, :retrieve_cache}}
  end

  @impl true
  def handle_continue(:retrieve_cache, state) do
    cmap =
      HostCore.Claims.Manager.get_claims()
      |> Enum.reduce(state.claims, fn claims, cmap ->
        Map.put(cmap, claims.sub, claims)
      end)

    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:claims, cmap})
    {:noreply, Map.put(state, :claims, cmap)}
  end

  @impl true
  def handle_call(:hosts_query, _from, state) do
    {:reply, state.hosts, state}
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
      if String.starts_with?(topic, "wasmbus.evt.") do
        handle_event(state, body)
      end

    {:noreply, state}
  end

  def get_hosts() do
    GenServer.call(:state_monitor, :hosts_query)
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

  @impl true
  def handle_cast({:cache_load_event, :linkdef_removed, ld}, state) do
    key = {ld["actor_id"], ld["contract_id"], ld["link_name"]}
    linkdefs = Map.delete(state.linkdefs, key)

    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:linkdefs, linkdefs})
    {:noreply, %State{state | linkdefs: linkdefs}}
  end

  @impl true
  def handle_cast({:cache_load_event, :linkdef_added, ld}, state) do
    key = {ld.actor_id, ld.contract_id, ld.link_name}
    map = %{values: ld.values, provider_key: ld.provider_id}

    linkdefs = Map.put(state.linkdefs, key, map)

    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:linkdefs, linkdefs})
    {:noreply, %State{state | linkdefs: linkdefs}}
  end

  @impl true
  def handle_cast({:cache_load_event, :claims_added, claims}, state) do
    cmap = Map.put(state.claims, claims.sub, claims)

    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:claims, cmap})
    {:noreply, %State{state | claims: cmap}}
  end

  @impl true
  def handle_cast({:cache_load_event, :ocimap_added, data}, state) do
    IO.puts("OCIMap added")
    IO.inspect(data)
    {:noreply, state}
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
    hosts = add_actor(pk, source_host, state.hosts)
    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:hosts, hosts})
    %State{state | hosts: hosts}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"public_key" => public_key, "instance_id" => _instance_id},
           datacontenttype: "application/json",
           source: source_host,
           type: "com.wasmcloud.lattice.actor_stopped"
         }
       ) do
    hosts = remove_actor(public_key, source_host, state.hosts)
    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:hosts, hosts})
    %State{state | hosts: hosts}
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
    hosts = add_provider(pk, link_name, contract_id, source_host, state.hosts)
    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:hosts, hosts})
    %State{state | hosts: hosts}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"link_name" => link_name, "public_key" => pk},
           datacontenttype: "application/json",
           source: _source_host,
           type: "com.wasmcloud.lattice.provider_stopped"
         }
       ) do
    instances =
      Map.get(state.providers, pk)
      |> Enum.filter(fn el -> el.link_name != link_name end)

    providers = Map.put(state.providers, pk, instances)

    PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:providers, providers})
    %State{state | providers: providers}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: %{"actors" => actors, "providers" => providers},
           datacontenttype: "application/json",
           source: source_host,
           type: "com.wasmcloud.lattice.host_heartbeat"
         }
       ) do
    Logger.info("Handling host heartbeat")

    current_host = Map.get(state.hosts, source_host)

    # TODO: Also ensure that actors don't exist in the dashboard that aren't in the health check
    actor_map =
      actors
      |> Enum.reduce(%{}, fn actor, actor_map ->
        actor_id = Map.get(actor, "actor")
        existing_actor = current_host |> Map.get(:actors) |> Map.get(actor_id)

        if existing_actor != nil && Map.get(existing_actor, :count) == Map.get(actor, "instances") do
          Map.put(actor_map, actor_id, existing_actor)
        else
          Map.put(actor_map, actor_id, %{
            count: Map.get(actor, "instances"),
            status: "Awaiting"
          })
        end
      end)

    # TODO: Also ensure that providers don't exist in the dashboard that aren't in the health check
    # Provider map is keyed by a tuple of the form
    # {public_key, link_name}
    provider_map =
      providers
      |> Enum.reduce(%{}, fn provider, provider_map ->
        provider_id = Map.get(provider, "public_key")
        link_name = Map.get(provider, "link_name")

        existing_provider =
          current_host |> Map.get(:providers) |> Map.get({provider_id, link_name})

        if existing_provider != nil do
          Map.put(provider_map, {provider_id, link_name}, existing_provider)
        else
          Map.put(
            provider_map,
            {Map.get(provider, "public_key"), Map.get(provider, "link_name")},
            %{
              contract_id: Map.get(provider, "contract_id"),
              status: "Awaiting"
            }
          )
        end
      end)

    host =
      if current_host == nil do
        %{
          actors: actor_map,
          providers: provider_map,
          # TODO: get labels from host inventory, ctl query
          labels: %{}
        }
      else
        %{
          actors: actor_map,
          providers: provider_map,
          labels: state.hosts |> Map.get(source_host) |> Map.get(:labels)
        }
      end

    hosts = Map.put(state.hosts, source_host, host)
    %State{state | hosts: hosts}
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: data,
           datacontenttype: "application/json",
           source: source_host,
           type: "com.wasmcloud.lattice.health_check_passed"
         }
       ) do
    public_key = Map.get(data, "public_key")
    Logger.info("Handling successful health check for #{public_key}")
    link_name = Map.get(data, "link_name")

    case update_status(public_key, link_name, source_host, state.hosts, "Healthy") do
      {:hosts, hosts} ->
        PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:hosts, hosts})
        %State{state | hosts: hosts}

      {:error, _err} ->
        state
    end
  end

  defp process_event(
         state,
         %Cloudevents.Format.V_1_0.Event{
           data: data,
           datacontenttype: "application/json",
           source: source_host,
           type: "com.wasmcloud.lattice.health_check_failed"
         }
       ) do
    public_key = Map.get(data, "public_key")
    Logger.info("Handling failed health check for #{public_key}")
    link_name = Map.get(data, "link_name")

    case update_status(public_key, link_name, source_host, state.hosts, "Unhealthy") do
      {:hosts, hosts} ->
        PubSub.broadcast(WasmcloudHost.PubSub, "lattice:state", {:hosts, hosts})
        %State{state | hosts: hosts}

      # Could not update hosts, don't change state
      {:error, _err} ->
        state
    end
  end

  defp update_status(public_key, link_name, source_host, hosts, new_status) do
    host_map = Map.get(hosts, source_host, %{})
    actors = Map.get(host_map, :actors, %{})
    providers = Map.get(host_map, :providers, %{})

    actor_map = Map.get(actors, public_key, nil)
    provider_map = Map.get(providers, {public_key, link_name}, nil)

    cond do
      actor_map != nil ->
        actor_map = Map.put(actor_map, :status, new_status)
        actors = Map.put(actors, public_key, actor_map)
        host_map = Map.put(host_map, :actors, actors)
        hosts = Map.put(hosts, source_host, host_map)
        {:hosts, hosts}

      provider_map != nil ->
        provider_map = Map.put(provider_map, :status, new_status)
        providers = Map.put(providers, {public_key, link_name}, provider_map)
        host_map = Map.put(host_map, :providers, providers)
        hosts = Map.put(hosts, source_host, host_map)
        {:hosts, hosts}

      true ->
        {:error, "Public key did not match running provider or actor"}
    end
  end

  # This map is keyed by provider public key, which contains a list of
  # maps with the keys "link_name", "contract_id", and "host_ids", as
  # shown below.
  # TODO: This is wrong
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
  def add_provider(pk, link_name, contract_id, source_host, previous_map) do
    # Get the source host and its current running providers
    host_map = Map.get(previous_map, source_host, %{})
    providers_map = Map.get(host_map, :providers, %{})

    provider_map = Map.get(providers_map, {pk, link_name}, nil)

    if provider_map == nil do
      providers_map =
        Map.put(
          provider_map,
          {pk, link_name},
          %{
            contract_id: contract_id,
            status: "Awaiting"
          }
        )

      host_map = Map.put(host_map, :providers, providers_map)
      Map.put(previous_map, source_host, host_map)
    else
      # Provider already exists with that link name and public key, no-op
      previous_map
    end
  end

  # This map is keyed with the actor public key and holds a map
  # containing a host ID mapping to the status of the actor on that
  # host and a total count on that host
  # TODO: this map is incorrect, fix
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
    # Retrieve inventory map for host
    host_map = Map.get(previous_map, host, %{})
    # Retrieve actor map, update count, update status
    actors_map = Map.get(host_map, :actors, %{})
    actor_map = Map.get(actors_map, pk, %{})
    new_count = Map.get(actor_map, :count, 0) + 1
    actor_map = Map.put(actor_map, :count, new_count)
    actor_map = Map.put(actor_map, :status, "Awaiting")
    actors_map = Map.put(actors_map, pk, actor_map)
    # Update host inventory with new actor information
    host_map = Map.put(host_map, :actors, actors_map)

    # Update hosts map with updated host
    Map.put(previous_map, host, host_map)
  end

  def remove_actor(pk, host, previous_map) do
    # Retrieve host inventory
    host_map = Map.get(previous_map, host, %{})
    actors_map = Map.get(host_map, :actors, %{})

    # Retrieve actor and current count
    actor_map = Map.get(actors_map, pk, %{})
    current_count = Map.get(actor_map, :count, nil)

    actors_map =
      case current_count do
        # Remove the actor from the host inventory
        1 ->
          Map.delete(actors_map, pk)

        # Actor was not found, no-op
        nil ->
          actors_map

        # Reduce actor count by 1
        _other ->
          actor_map = Map.put(actor_map, :count, current_count - 1)
          Map.put(actors_map, pk, actor_map)
      end

    host_map = Map.put(host_map, :actors, actors_map)
    Map.put(previous_map, host, host_map)
  end
end
