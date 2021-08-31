defmodule HostCoreTest.EventWatcher do
  require Gnat
  require Logger

  use GenServer

  @event_wait_interval 1_000

  defmodule State do
    defstruct [
      :topic,
      :sub,
      :events,
      :claims,
      :linkdefs,
      :ocirefs
    ]
  end

  @impl true
  def init(prefix) do
    purge_topic = "$JS.API.STREAM.PURGE.LATTICECACHE_#{prefix}"
    stream_topic = "lc.#{prefix}.>"

    case Gnat.request(:control_nats, purge_topic, []) do
      {:ok, %{body: body}} ->
        Logger.debug("Purged NATS stream for events watcher")

      {:error, :timeout} ->
        Logger.error("Failed to purge NATS stream for events watcher")
    end

    Registry.register(Registry.EventMonitorRegistry, "cache_loader_events", [])

    # Subscribe to lattice events stream
    topic = "wasmbus.evt.#{prefix}"
    {:ok, sub} = Gnat.sub(:control_nats, self(), topic)

    # Wait for first ping/pong
    Process.sleep(2_000)

    {:ok, %State{topic: topic, sub: sub, events: [], claims: %{}, linkdefs: %{}, ocirefs: %{}}}
  end

  @impl true
  # Receives events from wasmbus.evt.prefix and stores them for later processing
  def handle_info({:msg, %{body: body}}, state) do
    evt = Jason.decode!(body)
    events = [evt | state.events]

    {:noreply, %State{state | events: events}}
  end

  @impl true
  def handle_cast({:cache_load_event, :linkdef_removed, ld}, state) do
    key = {ld.actor_id, ld.contract_id, ld.link_name}
    linkdefs = Map.delete(state.linkdefs, key)

    {:noreply, %State{state | linkdefs: linkdefs}}
  end

  @impl true
  def handle_cast({:cache_load_event, :linkdef_added, ld}, state) do
    key = {ld.actor_id, ld.contract_id, ld.link_name}
    map = %{values: ld.values, provider_key: ld.provider_id}

    linkdefs = Map.put(state.linkdefs, key, map)
    Logger.debug("received linkdef")
    IO.inspect(linkdefs)

    {:noreply, %State{state | linkdefs: linkdefs}}
  end

  @impl true
  def handle_cast({:cache_load_event, :claims_added, claims}, state) do
    cmap = Map.put(state.claims, claims.sub, claims)

    {:noreply, %State{state | claims: cmap}}
  end

  @impl true
  def handle_cast({:cache_load_event, :ocimap_added, ocimap}, state) do
    ocirefs = Map.put(state.ocirefs, ocimap.oci_url, ocimap.public_key)
    {:noreply, %State{state | ocirefs: ocirefs}}
  end

  @impl true
  def terminate(_reason, state) do
    Gnat.unsub(:control_nats, state.sub)
  end

  @impl true
  def handle_call(:events, _from, state) do
    {:reply, state.events, state}
  end

  @impl true
  def handle_call(:linkdefs, _from, state) do
    {:reply, state.linkdefs, state}
  end

  def linkdefs(pid) do
    GenServer.call(pid, :linkdefs)
  end

  # Determines if `count` events with specified type and data parameters has occurred
  def assert_received?(pid, event_type, event_data, count \\ 1) do
    events_for_type(pid, event_type)
    |> find_matching_events(event_data)
    |> Enum.count() >= count
  end

  # Returns all events for a given event type, e.g.
  # `events_for_type(pid, "com.wasmcloud.lattice.actor_stopped")`
  def events_for_type(pid, type) do
    GenServer.call(pid, :events)
    |> Enum.filter(fn evt -> evt["type"] == type end)
  end

  # Finds all events matching the specified data parameters
  defp find_matching_events(events, data) do
    Enum.filter(events, fn evt -> data_matches?(evt["data"], data) end)
  end

  # Compares two sets of data, returning true if the event contains all matching data parameters
  defp data_matches?(event_data, data) do
    data
    |> Enum.map(fn {key, value} ->
      Map.get(event_data, key) == value
    end)
    |> Enum.all?()
  end

  # Returns a truthy value indicating if an actor with specified public key has started
  def actor_started?(pid, public_key) do
    assert_received?(pid, "com.wasmcloud.lattice.actor_started", %{"public_key" => public_key})
  end

  # Returns a truthy value indicating if an actor with specified public key has stopped
  def actor_stopped?(pid, public_key) do
    assert_received?(pid, "com.wasmcloud.lattice.actor_stopped", %{"public_key" => public_key})
  end

  # Returns a truthy value indicating if a provider with specified contract_id, link_name,
  # and public key has started
  def provider_started?(pid, contract_id, link_name, public_key) do
    assert_received?(pid, "com.wasmcloud.lattice.provider_started", %{
      "contract_id" => contract_id,
      "link_name" => link_name,
      "public_key" => public_key
    })
  end

  # Returns a truthy value indicating if a provider with specified link_name
  # and public key has stopped
  def provider_stopped?(pid, link_name, public_key) do
    assert_received?(pid, "com.wasmcloud.lattice.provider_stopped", %{
      "link_name" => link_name,
      "public_key" => public_key
    })
  end

  # Helper function to await an event using a truthy callback
  defp wait_for_event_received(pid, event_received, event_debug, timeout) do
    cond do
      timeout <= 0 ->
        Logger.debug("Timed out waiting for #{event_debug}")
        {:error, :timeout}

      event_received.() ->
        :ok

      true ->
        Logger.debug(
          "#{event_debug} event not received yet, retrying in #{@event_wait_interval}ms"
        )

        Process.sleep(@event_wait_interval)
        wait_for_event_received(pid, event_received, event_debug, timeout - @event_wait_interval)
    end
  end

  # Waits for a given event to occur with specified optional data until timeout
  # e.g. `wait_for_event(pid, :actor_started, %{"public_key" => "MASDASD"}, 30_000)`
  # Data is also optional, and will match on the first event received if not supplied.
  # The key-value pairs in `data` must match the CloudEvent data key-value pair
  def wait_for_event(pid, event, data \\ %{}, count \\ 1, timeout \\ 30_000) do
    wait_for_event_received(
      pid,
      fn ->
        assert_received?(pid, "com.wasmcloud.lattice.#{event}", data, count)
      end,
      event,
      timeout
    )
  end

  # Waits for an `actor_started` event to occur with the given public key until timeout
  def wait_for_actor_start(pid, public_key, timeout \\ 30_000) do
    wait_for_event_received(
      pid,
      fn -> actor_started?(pid, public_key) end,
      "actor start",
      timeout
    )
  end

  # Waits for an `actor_stopped` event to occur with the given public key until timeout
  def wait_for_actor_stop(pid, public_key, timeout \\ 30_000) do
    wait_for_event_received(pid, fn -> actor_stopped?(pid, public_key) end, "actor stop", timeout)
  end

  # Waits for an `provider_started` event to occur with the given contract_id, link_name,
  # and public key until timeout
  def wait_for_provider_start(pid, contract_id, link_name, public_key, timeout \\ 30_000) do
    wait_for_event_received(
      pid,
      fn -> provider_started?(pid, contract_id, link_name, public_key) end,
      "provider start",
      timeout
    )
  end

  # Waits for an `provider_stopped` event to occur with the given link_name
  # and public key until timeout
  def wait_for_provider_stop(pid, link_name, public_key, timeout \\ 30_000) do
    wait_for_event_received(
      pid,
      fn -> provider_stopped?(pid, link_name, public_key) end,
      "provider stop",
      timeout
    )
  end

  # Waits for a linkdef to be established with given parameters until timeout
  def wait_for_linkdef(pid, actor_id, contract_id, link_name, timeout \\ 30_000) do
    linkdef = Map.get(linkdefs(pid), {actor_id, contract_id, link_name}, nil)
    Logger.debug("Waiting for linkdef")
    IO.inspect(linkdefs(pid))
    IO.inspect(linkdef)
    IO.inspect(:ets.tab2list(:linkdef_table))

    cond do
      linkdef != nil ->
        :ok

      timeout <= 0 ->
        Logger.debug("Timed out waiting for linkdef")
        {:error, :timeout}

      true ->
        Logger.debug("Linkdef not received yet, retrying in #{@event_wait_interval}ms")

        Process.sleep(@event_wait_interval)
        wait_for_linkdef(pid, actor_id, contract_id, link_name, timeout - @event_wait_interval)
    end
  end
end
