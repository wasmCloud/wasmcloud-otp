defmodule HostCore.E2E.EchoTest do
  use ExUnit.Case, async: false

  @echo_key "MADQAFWOOOCZFDKYEYHC7AUQKDJTP32XUC5TDSMN4JLTDTU2WXBVPG4G"
  @httpserver_key "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
  @httpserver_link "default"
  @httpserver_contract "wasmcloud:httpserver"
  @httpserver_path "priv/providers/httpserver"

  test "echo roundtrip" do
    {:ok, bytes} = File.read("priv/actors/echo_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    on_exit(fn -> HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 1) end)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_executable_provider(
        @httpserver_path,
        @httpserver_key,
        @httpserver_link,
        @httpserver_contract
      )

    on_exit(fn ->
      HostCore.Providers.ProviderSupervisor.terminate_provider(@httpserver_key, @httpserver_link)
    end)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key)
      |> length

    assert actor_count == 1

    assert HostCore.Providers.ProviderSupervisor.all_providers() == [
             {@httpserver_key, @httpserver_link, @httpserver_contract}
           ]

    Process.sleep(1000)

    :ok =
      HostCore.LinkdefsManager.put_link_definition(
        @echo_key,
        @httpserver_contract,
        @httpserver_link,
        @httpserver_key,
        %{PORT: "8080"}
      )

    Process.sleep(1000)

    HTTPoison.start()
    {:ok, resp} = HTTPoison.get("http://localhost:8080/foo/bar")

    Process.sleep(1000)
  end
end
