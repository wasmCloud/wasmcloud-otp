defmodule HostCore.ControlInterface.ACL do
  @moduledoc false

  def all_actors() do
    HostCore.Actors.ActorSupervisor.all_actors()
    |> Enum.map(fn {id, pids} ->
      name = get_name(id)
      revision = get_revision(id)

      instances =
        pids
        |> Enum.map(fn pid ->
          %{
            annotations: HostCore.Actors.ActorModule.annotations(pid),
            instance_id: HostCore.Actors.ActorModule.instance_id(pid),
            revision: revision
          }
        end)

      %{
        id: id,
        image_ref: HostCore.Actors.ActorModule.ociref(Enum.at(pids, 0)),
        name: name,
        instances: instances
      }
    end)
  end

  def all_providers() do
    HostCore.Providers.ProviderSupervisor.all_providers()
    |> Enum.map(fn {pid, pk, link, _contract, instance_id} ->
      name = get_name(pk)
      revision = get_revision(pk)

      %{
        id: pk,
        image_ref: HostCore.Providers.ProviderModule.ociref(pid),
        link_name: link,
        name: name,
        instance_id: instance_id,
        annotations: HostCore.Providers.ProviderModule.annotations(pid),
        revision: revision
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
      [claims] -> String.to_integer(claims.rev)
      _ -> 0
    end
  end

  def get_name(pk) do
    case find_claims_for_pk(pk) do
      [claims] -> claims.name
      _ -> "N/A"
    end
  end

  def get_image_ref(pk) do
    case find_oci_for_pk(pk) do
      [[oci]] -> oci
      _ -> nil
    end
  end
end
