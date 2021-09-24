defmodule HostCore.ControlInterface.ACL do
  @moduledoc false

  def all_actors() do
    HostCore.Actors.ActorSupervisor.all_actors()
    |> Enum.flat_map(fn {id, pids} ->
      revision = get_revision(id)

      pids
      |> Enum.map(fn pid ->
        %{
          id: id,
          revision: revision,
          image_ref: HostCore.Actors.ActorModule.ociref(pid),
          instance_id: HostCore.Actors.ActorModule.instance_id(pid)
        }
      end)
    end)
  end

  def all_providers() do
    # TODO: retrieve revision information for provider
    HostCore.Providers.ProviderSupervisor.all_providers()
    |> Enum.map(fn {pid, pk, link, _contract, instance_id} ->
      %{
        id: pk,
        link_name: link,
        revision: 0,
        image_ref: HostCore.Providers.ProviderModule.ociref(pid),
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
      [claims] -> String.to_integer(claims.rev)
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
