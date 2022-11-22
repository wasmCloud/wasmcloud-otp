defmodule HostCore.ControlInterface.ACL do
  @moduledoc false

  # def all_actors() do
  #   HostCore.Actors.ActorSupervisor.all_actors()
  #   |> Enum.map(fn {id, pids} ->
  #     name = get_name(id)
  #     revision = get_revision(id)

  #     instances =
  #       pids
  #       |> Enum.map(fn pid ->
  #         %{
  #           annotations: HostCore.Actors.ActorModule.annotations(pid),
  #           instance_id: HostCore.Actors.ActorModule.instance_id(pid),
  #           revision: revision
  #         }
  #       end)

  #     %{
  #       id: id,
  #       image_ref: HostCore.Actors.ActorModule.ociref(Enum.at(pids, 0)),
  #       name: name,
  #       instances: instances
  #     }
  #   end)
  # end

  def convert_inv_actors(inv, lattice_prefix) do
    actors =
      for {id, pids} <- inv.actors do
        claims = find_claims_for_pk(lattice_prefix, id)
        revision = String.to_integer(claims.rev)
        name = claims.name

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
      end

    %{inv | actors: actors}
  end

  # def all_providers() do
  #   HostCore.Providers.ProviderSupervisor.all_providers()
  #   |> Enum.map(fn {pid, pk, link, _contract, instance_id} ->
  #     name = get_name(pk)
  #     revision = get_revision(pk)

  #     %{
  #       id: pk,
  #       image_ref: HostCore.Providers.ProviderModule.ociref(pid),
  #       link_name: link,
  #       name: name,
  #       instance_id: instance_id,
  #       annotations: HostCore.Providers.ProviderModule.annotations(pid),
  #       revision: revision
  #     }
  #   end)
  # end

  def convert_inv_providers(inv, lattice_prefix) do
    providers =
      for {pid, pk, link, _contract, instance_id} <- inv.providers do
        claims = find_claims_for_pk(lattice_prefix, pk)
        name = claims.name
        revision = String.to_integer(claims.rev)

        %{
          id: pk,
          image_ref: HostCore.Providers.ProviderModule.ociref(pid),
          link_name: link,
          name: name,
          instance_id: instance_id,
          annotations: HostCore.Providers.ProviderModule.annotations(pid),
          revision: revision
        }
      end

    %{inv | providers: providers}
  end

  def find_oci_for_pk(pk) do
    :ets.match(:refmap_table, {:"$1", pk})
  end

  def find_claims_for_pk(lattice_prefix, pk) do
    case HostCore.Claims.Manager.lookup_claims(lattice_prefix, pk) do
      {:ok, %{} = c} -> c
      :error -> nil
    end
  end
end
