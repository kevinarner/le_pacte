-- Migration : suppression d'un pacte (Swend) par l'une des deux parties.
--
-- À exécuter dans Supabase SQL Editor (aucun accès direct à la base
-- depuis Claude Code, cf. convention du projet).
--
-- Pourquoi une fonction SECURITY DEFINER plutôt que des policies DELETE
-- classiques : les remplaçants sont cloisonnés par côté (chaque partie ne
-- voit/modifie que ses propres remplaçants via RLS), mais supprimer un
-- pacte doit effacer les remplaçants des DEUX côtés ainsi que tous les
-- messages qui leur sont rattachés. Une fonction SECURITY DEFINER,
-- vérifiant elle-même que l'appelant est bien l'initiateur ou le
-- destinataire du pacte, reproduit le pattern déjà utilisé dans ce
-- projet (annuler_si_double_absence, synchroniser_remplacants_caches...).

create or replace function supprimer_pacte(p_pacte_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_est_partie boolean;
begin
  select exists (
    select 1 from pactes
    where id = p_pacte_id
      and (initiateur_id = v_uid or destinataire_id = v_uid)
  ) into v_est_partie;

  if not v_est_partie then
    raise exception 'Non autorisé à supprimer ce pacte';
  end if;

  delete from messages
  where remplacant_id in (
    select id from remplacants where pacte_id = p_pacte_id
  );

  delete from remplacants where pacte_id = p_pacte_id;

  delete from pactes where id = p_pacte_id;
end;
$$;

grant execute on function supprimer_pacte(uuid) to authenticated;
