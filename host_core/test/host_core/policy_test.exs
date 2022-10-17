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
  @echo_key HostCoreTest.Constants.echo_key()
  @echo_ociref HostCoreTest.Constants.echo_ociref()

  # Setup to ensure policy resources are started beforehand
  setup_all do
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

    [policy_setup: true]
  end

  @source_provider %{
    publicKey: "VD4NYOOHH5ZP7VJUGQ5E5JO2BEALBZAR6OPIRQFGIKVLU6UJQYWCDP63",
    contractId: "wasmcloud:test",
    linkName: "default",
    capabilities: [],
    issuer: "ADT2YUKCRQUGXXM73BBWVI33E4QLQX2LWRCMSC3ZUSCVKBZ6KQMJNU3L",
    issuedOn: "September 21",
    expiresAt: DateTime.utc_now() |> DateTime.add(60),
    expired: false
  }

  @target_actor %{
    publicKey: "MD7OKVK3BJQSS43CPGX2GGQ36RHGMEYSKD3OHSW2WWLWTZJYEQM4IIGU",
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
             requestId: ""
           }
  end

  # :passthrough enables mocking a single function from the module and still accessing said module
  test_with_mock "can deny policy by default when timing out",
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
             permitted: false,
             # as of Gnat 1.6.0 we get support for quick abort due to no responders
             message: "No responders to policy request (policy server not listening?)",
             # Request ID is generated during evaluation, so grab it for comparison
             requestId: decision.requestId
           }

    decision_same =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider,
        @target_actor,
        @perform_invocation
      )

    assert decision_same == %{
             permitted: false,
             message: "No responders to policy request (policy server not listening?)",
             # Request ID is generated during evaluation, so grab it for comparison
             requestId: decision_same.requestId
           }
  end

  test_with_mock "can properly fail closed when policy requests are invalid",
                 HostCore.Policy.Manager,
                 [:passthrough],
                 policy_topic: fn -> {:ok, "foo.bar"} end do
    invalid_source =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider |> Map.delete(:publicKey),
        @target_actor,
        @perform_invocation
      )

    assert invalid_source == %{
             permitted: false,
             message: "Invalid source argument, missing required fields: publicKey",
             requestId: invalid_source.requestId
           }

    invalid_target =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider,
        @target_actor |> Map.delete(:issuer),
        @perform_invocation
      )

    assert invalid_target == %{
             permitted: false,
             message: "Invalid target argument, missing required fields: issuer",
             requestId: invalid_target.requestId
           }

    invalid_action =
      HostCore.Policy.Manager.evaluate_action(
        @source_provider,
        @target_actor,
        [%{"mine_bitcoin" => true, "h4x0rscr1pt" => "./mine_bitcoin.sh"}]
      )

    assert invalid_action == %{
             permitted: false,
             message: "Invalid action argument, action was not a string",
             requestId: invalid_action.requestId
           }
  end

  test_with_mock "can request policy evaluations and deny actions",
                 HostCore.Policy.Manager,
                 [:passthrough],
                 policy_topic: fn -> {:ok, "wasmcloud.policy.evaluator"} end do
    on_exit(fn -> HostCore.Host.purge() end)

    # Hack, you aren't supposed to run a policy actor on a policy host. This is
    # allowing the policy actor to receive the invocation from the NATS provider
    action = "perform_invocation"

    source = %{
      capabilities: "",
      contractId: "wasmcloud:messaging",
      expiresAt: nil,
      expired: false,
      issuedOn: nil,
      issuer: "ACOJJN6WUP4ODD75XEBKKTCCUJJCY5ZKQ56XVKYK4BEJWGVAOOQHZMCW",
      linkName: "default",
      publicKey: "VADNMSIML2XGO2X4TPIONTIC55R2UUQGPPDZPAVSC2QD7E76CR77SPW7"
    }

    target = %{
      contractId: "",
      issuer: "ADANTQNWB7RCDOITC7Y3NJ3I7NPEJH6L5PRVG4TPYZXI45Z3K22VHMTY",
      linkName: "",
      publicKey: "MCX7HXCVATHJQRQLCCKV57R34V726FYRTDQL2QKPHXLYFWGOUE2LWRE3"
    }

    :ets.insert(
      :policy_table,
      {{source, target, action}, %{permitted: true, requestId: UUID.uuid4(), message: "shhhhhh"}}
    )

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
