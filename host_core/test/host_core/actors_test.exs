defmodule HostCore.ActorsTest do
  use ExUnit.Case
  doctest HostCore.Actors
  @echo_key "MADQAFWOOOCZFDKYEYHC7AUQKDJTP32XUC5TDSMN4JLTDTU2WXBVPG4G"

  test "can load actors" do
    {:ok, bytes} = File.read("priv/actors/echo_s.wasm")
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    actor_count =
      Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key)
      |> length

    assert actor_count == 5
    HostCore.Actors.ActorSupervisor.terminate_actor(@echo_key, 5)

    assert Map.get(HostCore.Actors.ActorSupervisor.all_actors(), @echo_key) == nil
  end
end
