defmodule HostCore.ControlInterface.ACL do
  def all_actors() do
    HostCore.Actors.ActorSupervisor.all_actors()
    |> Enum.map(fn {k, _v} -> %{id: k, revision: get_revision(k), image_ref: get_image_ref(k)} end)
  end

  def all_providers() do
    HostCore.Providers.ProviderSupervisor.all_providers()
    |> Enum.map(fn {pk, link, _contract} ->
      %{id: pk, link_name: link, revision: get_revision(pk), image_ref: get_image_ref(pk)}
    end)
  end

  def find_oci_for_pk(pk) do
    :ets.match(:refmap_table, {:"$1", pk})
  end

  def find_claims_for_pk(pk) do
    :ets.match(:claims_table, {pk, "$2"})
  end

  defp get_revision(pk) do
    case find_claims_for_pk(pk) do
      [[claims]] -> claims.revision
      _ -> 0
    end
  end

  defp get_image_ref(pk) do
    case find_oci_for_pk(pk) do
      [[oci]] -> oci
      _ -> nil
    end
  end
end
