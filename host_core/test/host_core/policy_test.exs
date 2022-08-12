defmodule HostCore.PolicyTest do
  # Any test suite that relies on things like querying the actor count or the provider
  # count will need to be _synchronous_ tests so that other tests that rely on that same
  # information won't get bad/confusing results.
  use ExUnit.Case, async: false

  import Mock

  @policy_key HostCoreTest.Constants.policy_key()
  @policy_path HostCoreTest.Constants.policy_path()
  @nats_key HostCoreTest.Constants.nats_key()
  @nats_ociref HostCoreTest.Constants.nats_ociref()
  @echo_ociref HostCoreTest.Constants.echo_ociref()

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    [
      evt_watcher: evt_watcher
    ]
  end

  @source_provider %{
    public_key: "VD4NYOOHH5ZP7VJUGQ5E5JO2BEALBZAR6OPIRQFGIKVLU6UJQYWCDP63",
    contract_id: "wasmcloud:test",
    link_name: "default",
    capabilities: [],
    issuer: "ADT2YUKCRQUGXXM73BBWVI33E4QLQX2LWRCMSC3ZUSCVKBZ6KQMJNU3L",
    issued_on: "September 21",
    expires_in_mins: 60
  }

  @target_actor %{
    public_key: "MD7OKVK3BJQSS43CPGX2GGQ36RHGMEYSKD3OHSW2WWLWTZJYEQM4IIGU",
    issuer: "ADT2YUKCRQUGXXM73BBWVI33E4QLQX2LWRCMSC3ZUSCVKBZ6KQMJNU3L"
  }

  @perform_invocation "perform_invocation"

  test "can allow policy requests when disabled" do
    assert HostCore.Policy.Manager.evaluate_action(
             @source_provider,
             @target_actor,
             @perform_invocation
           ) == %{
             permitted: true,
             message: "Policy evaluation disabled, allowing action",
             request_id: ""
           }
  end

  # :passthrough enables mocking a single function from the module and still accessing said module
  test_with_mock "can allow policy by default when timing out",
                 HostCore.Policy.Manager,
                 [:passthrough],
                 policy_topic: fn -> {:ok, "foo.bar"} end do
    decision =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider,
        @target_actor,
        @perform_invocation
      )

    assert decision == %{
             permitted: true,
             message: "Policy request timed out, allowing action",
             # Request ID is generated during evaluation, so grab it for comparison
             request_id: decision.request_id
           }

    decision_faster =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider,
        @target_actor,
        @perform_invocation
      )

    assert decision_faster == %{
             permitted: true,
             message: "Policy request timed out, allowing action",
             # Request ID is generated during evaluation, so grab it for comparison
             request_id: decision_faster.request_id
           }
  end

  test_with_mock "can properly detect fail open when policy requests are invalid",
                 HostCore.Policy.Manager,
                 [:passthrough],
                 policy_topic: fn -> {:ok, "foo.bar"} end do
    invalid_source =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider |> Map.delete(:public_key),
        @target_actor,
        @perform_invocation
      )

    assert invalid_source == %{
             permitted: true,
             message: "Invalid source argument, missing required fields: public_key",
             request_id: invalid_source.request_id
           }

    invalid_target =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider,
        @target_actor |> Map.delete(:issuer),
        @perform_invocation
      )

    assert invalid_target == %{
             permitted: true,
             message: "Invalid target argument, missing required fields: issuer",
             request_id: invalid_target.request_id
           }

    invalid_action =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider,
        @target_actor,
        [%{"mine_bitcoin" => true, "h4x0rscr1pt" => "./mine_bitcoin.sh"}]
      )

    assert invalid_action == %{
             permitted: true,
             message: "Invalid action argument, action was not a string",
             request_id: invalid_action.request_id
           }
  end

  test_with_mock "can request policy evaluations and deny actions",
                 %{:evt_watcher => _evt_watcher},
                 HostCore.Policy.Manager,
                 [:passthrough],
                 policy_topic: fn -> {:ok, "wasmcloud.policy.evaluator"} end do
    on_exit(fn -> HostCore.Host.purge() end)

    HostCore.Linkdefs.Manager.put_link_definition(
      @policy_key,
      "wasmcloud:messaging",
      "default",
      @nats_key,
      %{
        "SUBSCRIPTION" => "wasmcloud.policy.evaluator"
      }
    )

    {:ok, bytes} = File.read(@policy_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    {:ok, _pid} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
        @nats_ociref,
        "default"
      )

    :timer.sleep(2000)

    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor_from_oci(@echo_ociref)

    {:error,
     "Starting actor MB2ZQB6ROOMAYBO4ZCTFYWN7YIVBWA3MTKZYAQKJMTIHE2ELLRW2E3ZW denied: Issuer was not the official wasmCloud issuer"} =
      HostCore.Actors.ActorSupervisor.start_actor_from_oci("ghcr.io/brooksmtownsend/wadice:0.1.0")

    {:error,
     "Starting provider VAHMIAAVLEZLKHF4CZJVBVBGGZTWGUUKBCH3MABLNMPPUPA6CJ2HSJCT denied: Issuer was not the official wasmCloud issuer"} =
      HostCore.Providers.ProviderSupervisor.start_provider_from_oci(
        "ghcr.io/brooksmtownsend/factorial:0.1.0",
        "default"
      )

    # Ensure the host doesn't start the actor that's denied
    assert !(HostCore.Actors.ActorSupervisor.all_actors()
             |> Map.keys()
             |> Enum.any?(fn public_key ->
               public_key == "MB2ZQB6ROOMAYBO4ZCTFYWN7YIVBWA3MTKZYAQKJMTIHE2ELLRW2E3ZW"
             end))

    # Ensure the host doesn't start the provider that's denied
    assert !(HostCore.Providers.ProviderSupervisor.all_providers()
             |> Enum.any?(fn {_, public_key, _, _, _} ->
               public_key == "VAHMIAAVLEZLKHF4CZJVBVBGGZTWGUUKBCH3MABLNMPPUPA6CJ2HSJCT"
             end))
  end
end
