defmodule HostCore.ControlInterface.ACL do
  @moduledoc false

  alias HostCore.Actors.ActorModule
  alias HostCore.Claims.Manager
  alias HostCore.Providers.ProviderModule

  def convert_inv_actors(inv, lattice_prefix) do
    actors =
      for {id, pids} <- inv.actors do
        claims = find_claims_for_pk(lattice_prefix, id)
        revision = String.to_integer(claims.rev)
        name = claims.name

        raw_instances = Enum.map(pids, fn pid -> ActorModule.full_state(pid) end)

        instances =
          Enum.map(raw_instances, fn state ->
            %{
              annotations: state.annotations,
              instance_id: state.instance_id,
              revision: revision
            }
          end)

        %{
          id: id,
          image_ref: pids |> Enum.at(0) |> ActorModule.ociref(),
          name: name,
          instances: instances
        }
      end

    %{inv | actors: actors}
  end

  def convert_inv_providers(inv, lattice_prefix) do
    providers =
      for {pid, pk, link, _contract, instance_id} <- inv.providers do
        claims = find_claims_for_pk(lattice_prefix, pk)
        name = claims.name
        revision = String.to_integer(claims.rev)

        %{
          id: pk,
          image_ref: ProviderModule.ociref(pid),
          contract_id: ProviderModule.contract_id(pid),
          link_name: link,
          name: name,
          instance_id: instance_id,
          annotations: ProviderModule.annotations(pid),
          revision: revision
        }
      end

    %{inv | providers: providers}
  end

  def find_oci_for_pk(pk) do
    :ets.match(:refmap_table, {:"$1", pk})
  end

  def find_claims_for_pk(lattice_prefix, pk) do
    case Manager.lookup_claims(lattice_prefix, pk) do
      {:ok, %{} = c} -> c
      :error -> nil
    end
  end
end
