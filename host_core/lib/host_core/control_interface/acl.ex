defmodule HostCore.ControlInterface.ACL do
  def all_actors() do
    HostCore.Actors.ActorSupervisor.all_actors()
    |> Enum.map(fn {k, v} ->
      %{
        id: k,
        revision: get_revision(k),
        image_ref: get_image_ref(k),
        instance_id: HostCore.Actors.ActorModule.instance_id(v)
      }
    end)
  end

  def all_providers() do
    HostCore.Providers.ProviderSupervisor.all_providers()
    |> Enum.map(fn {pk, link, _contract, instance_id} ->
      %{
        id: pk,
        link_name: link,
        revision: get_revision(pk),
        image_ref: get_image_ref(pk),
        instance_id: instance_id
      }
    end)
  end

  def find_oci_for_pk(pk) do
    :ets.match(:refmap_table, {:"$1", pk})
  end

  def find_claims_for_pk(pk) do
    case :ets.lookup(:claims_table, pk) do
      [{_pk, claims}] -> [claims]
      _ -> nil
    end
  end

  def get_revision(pk) do
    case find_claims_for_pk(pk) do
      [claims] -> claims.rev
      _ -> 0
    end
  end

  def get_image_ref(pk) do
    case find_oci_for_pk(pk) do
      [[oci]] -> oci
      _ -> nil
    end
  end
end
