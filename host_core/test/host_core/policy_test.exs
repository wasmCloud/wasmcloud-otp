defmodule HostCore.PolicyTest do
  # TODO
  # at the moment, the way this test is organized, none of the NATS providers on any of the test
  # hosts will fully shut down

  use ExUnit.Case, async: false

  alias HostCore.Actors.ActorSupervisor
  alias HostCore.Jetstream.Client, as: JetstreamClient
  alias HostCore.Providers.ProviderSupervisor
  alias HostCore.Vhost.VirtualHost

  import Mock
  import HostCoreTest.Common, only: [sudo_make_me_a_host: 1, cleanup: 2]

  @policy_key HostCoreTest.Constants.policy_key()
  @policy_path HostCoreTest.Constants.policy_path()
  @nats_key HostCoreTest.Constants.nats_key()
  @nats_ociref HostCoreTest.Constants.nats_ociref()
  @echo_key HostCoreTest.Constants.echo_key()
  @echo_ociref HostCoreTest.Constants.echo_ociref()

  # This creates a host in the "policyhome" lattice that runs a policy
  # actor listening on wasmcloud.policy.evaluator
  setup_all do
    lattice_prefix = "policyhome"
    {:ok, pid} = sudo_make_me_a_host(lattice_prefix)
    config = VirtualHost.config(pid)

    HostCore.Linkdefs.Manager.put_link_definition(
      lattice_prefix,
      @policy_key,
      "wasmcloud:messaging",
      "default",
      @nats_key,
      %{
        "SUBSCRIPTION" => "wasmcloud.policy.evaluator"
      }
    )

    {:ok, bytes} = File.read(@policy_path)
    {:ok, _pid} = ActorSupervisor.start_actor(bytes, config.host_key)

    {:ok, _pid} =
      ProviderSupervisor.start_provider_from_oci(
        config.host_key,
        @nats_ociref,
        "default"
      )

    :timer.sleep(2000)

    [policy_setup: true]
  end

  setup do
    {:ok, test_pid} = sudo_make_me_a_host(UUID.uuid4())
    test_config = VirtualHost.config(test_pid)
    [hconfig: test_config, host_pid: test_pid]
  end

  @source_provider %{
    publicKey: "VD4NYOOHH5ZP7VJUGQ5E5JO2BEALBZAR6OPIRQFGIKVLU6UJQYWCDP63",
    contractId: "wasmcloud:test",
    linkName: "default",
    capabilities: [],
    issuer: "ADT2YUKCRQUGXXM73BBWVI33E4QLQX2LWRCMSC3ZUSCVKBZ6KQMJNU3L",
    issuedOn: "September 21",
    expiresAt: DateTime.add(DateTime.utc_now(), 60),
    expired: false
  }

  @target_actor %{
    publicKey: "MD7OKVK3BJQSS43CPGX2GGQ36RHGMEYSKD3OHSW2WWLWTZJYEQM4IIGU",
    issuer: "ADT2YUKCRQUGXXM73BBWVI33E4QLQX2LWRCMSC3ZUSCVKBZ6KQMJNU3L"
  }

  @perform_invocation "perform_invocation"

  test "can allow policy requests when disabled" do
    config = HostCoreTest.Common.default_vhost_config()
    config = %{config | lattice_prefix: UUID.uuid4()}

    assert HostCore.Policy.Manager.evaluate_action(
             config,
             @source_provider,
             @target_actor,
             @perform_invocation
           ) == %{
             permitted: true,
             message: "Policy evaluation disabled, allowing action",
             requestId: ""
           }

    JetstreamClient.delete_kv_bucket("policyhome", nil)
  end

  # :passthrough enables mocking a single function from the module and still accessing said module
  test_with_mock "can deny policy by default when timing out",
                 %{:hconfig => config, :host_pid => pid},
                 HostCore.Policy.Manager,
                 [:passthrough],
                 policy_topic: fn _config -> {:ok, "foo.bar"} end do
    on_exit(fn ->
      cleanup(pid, config)
      :timer.sleep(700)
    end)

    decision =
      HostCore.Policy.Manager.evaluate_action(
        config,
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
        config,
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
                 %{:hconfig => config, :host_pid => pid},
                 HostCore.Policy.Manager,
                 [:passthrough],
                 policy_topic: fn _config -> {:ok, "foo.bar"} end do
    on_exit(fn ->
      cleanup(pid, config)
      :timer.sleep(700)
    end)

    invalid_source =
      HostCore.Policy.Manager.evaluate_action(
        config,
        Map.delete(@source_provider, :publicKey),
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
        config,
        @source_provider,
        Map.delete(@target_actor, :issuer),
        @perform_invocation
      )

    assert invalid_target == %{
             permitted: false,
             message: "Invalid target argument, missing required fields: issuer",
             requestId: invalid_target.requestId
           }

    invalid_action =
      HostCore.Policy.Manager.evaluate_action(
        config,
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

  # TODO: need to figure out why this test fails - currently it looks like the policy evaluation
  # failure is causing something to terminate and so we're not getting the errors we expect.
  #

  # test_with_mock "can request policy evaluations and deny actions",
  #                %{:hconfig => config, :host_pid => pid},
  #                HostCore.Policy.Manager,
  #                [:passthrough],
  #                policy_topic: fn _config -> {:ok, "wasmcloud.policy.evaluator"} end do
  #   on_exit(fn ->
  #     cleanup(pid, config)
  #     :timer.sleep(700)
  #   end)

  #   # Hack, you aren't supposed to run a policy actor on a policy host. This is
  #   # allowing the policy actor to receive the invocation from the NATS provider
  #   action = "perform_invocation"

  #   source = %{
  #     capabilities: "",
  #     contractId: "wasmcloud:messaging",
  #     expiresAt: nil,
  #     expired: false,
  #     issuedOn: nil,
  #     issuer: "ACOJJN6WUP4ODD75XEBKKTCCUJJCY5ZKQ56XVKYK4BEJWGVAOOQHZMCW",
  #     linkName: "default",
  #     publicKey: "VADNMSIML2XGO2X4TPIONTIC55R2UUQGPPDZPAVSC2QD7E76CR77SPW7"
  #   }

  #   target = %{
  #     contractId: "",
  #     issuer: "ADANTQNWB7RCDOITC7Y3NJ3I7NPEJH6L5PRVG4TPYZXI45Z3K22VHMTY",
  #     linkName: "",
  #     publicKey: "MCX7HXCVATHJQRQLCCKV57R34V726FYRTDQL2QKPHXLYFWGOUE2LWRE3"
  #   }

  #   :ets.insert(
  #     :policy_table,
  #     {{source, target, action, config.lattice_prefix},
  #      %{permitted: true, requestId: UUID.uuid4(), message: "shhhhhh"}}
  #   )

  #   {:error,
  #    "Starting actor MB2ZQB6ROOMAYBO4ZCTFYWN7YIVBWA3MTKZYAQKJMTIHE2ELLRW2E3ZW denied: "
  #   <> "Issuer was not the official wasmCloud issuer"} =
  #     ActorSupervisor.start_actor_from_oci(
  #       config.host_key,
  #       "ghcr.io/brooksmtownsend/wadice:0.1.0"
  #     )

  #   {:error,
  #    "Starting provider VAHMIAAVLEZLKHF4CZJVBVBGGZTWGUUKBCH3MABLNMPPUPA6CJ2HSJCT denied: "
  #     <> "Issuer was not the official wasmCloud issuer"} =
  #     ProviderSupervisor.start_provider_from_oci(
  #       config.host_key,
  #       "ghcr.io/brooksmtownsend/factorial:0.1.0",
  #       "default"
  #     )

  #   # Ensure the host doesn't start the actor that's denied
  #   assert !(ActorSupervisor.all_actors(config.host_key)
  #            |> Map.keys()
  #            |> Enum.any?(fn public_key ->
  #              public_key == "MB2ZQB6ROOMAYBO4ZCTFYWN7YIVBWA3MTKZYAQKJMTIHE2ELLRW2E3ZW"
  #            end))

  #   # Ensure the host doesn't start the provider that's denied
  #   assert !(ProviderSupervisor.all_providers(config.host_key)
  #            |> Enum.any?(fn {_, public_key, _, _, _} ->
  #              public_key == "VAHMIAAVLEZLKHF4CZJVBVBGGZTWGUUKBCH3MABLNMPPUPA6CJ2HSJCT"
  #            end))
  # end
end
