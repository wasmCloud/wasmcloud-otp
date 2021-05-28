defmodule HostCore.Providers.ProviderModule do
    use GenServer, restart: :transient    
    require Logger

    defmodule State do
        defstruct [:os_port, :os_pid]
    end

    @doc """
    Starts the provider module assuming it is an executable file
    """
    def start_link(opts) do
        GenServer.start_link(__MODULE__, opts)        
    end


    @impl true
    def init({:executable, path, public_key, link_name}) do
        Logger.info("Starting executable capability provider at  '#{path}'")
        port = Port.open({:spawn, "#{path}"}, [:binary])
        {:os_pid, pid} = Port.info(port, :os_pid)        

        publish_provider_started(public_key, link_name)

        {:ok, %State{ os_port: port, os_pid: pid}}
    end  

    @impl true
    def terminate(reason, state) do
        Logger.info("Terminating provider #{reason}")
        if state.os_pid != nil do
            System.cmd("kill", ["-9", "#{state.os_pid}"])
        end

        nil
    end
    
    @impl true
    def handle_info({_ref, {:data, logline}}, state) do
        Logger.info("Provider: #{logline}")

        {:noreply, state}
    end
    
    def handle_info({:msg,
        %{
            body: body,            
            reply_to: reply_to,            
            topic: topic,            
        }}, state) do
        Logger.info("Received invocation on #{topic}")
        {:noreply, state}
    end    

    def handle_info({_ref, msg}, state) do
        Logger.info(msg)

        {:noreply, state}
    end

    defp lattice_subscribe(public_key, link_name) do
        prefix = HostCore.Host.lattice_prefix()
        {:ok, _subscription} = Gnat.sub(:lattice_nats, self(), 
            "wasmbus.rpc.#{prefix}.#{public_key}.#{link_name}")
    end

    defp publish_provider_started(pk, link_name) do
        prefix = HostCore.Host.lattice_prefix()
        stamp = DateTime.utc_now() |> DateTime.to_iso8601

        host = HostCore.Host.host_key()        
        msg = %{
            specversion: "1.0",
            time: stamp,
            type: "com.wasmcloud.lattice.provider_started",
            source: "#{host}",
            datacontenttype: "application/json",
            id: UUID.uuid4(),
            data: %{
                public_key: pk,
                link_name: link_name
            }
        } 
        |> Cloudevents.from_map!()
        |> Cloudevents.to_json()
        topic = "wasmbus.ctl.#{prefix}.events"

        Gnat.pub(:control_nats, topic, msg)
    end

end
