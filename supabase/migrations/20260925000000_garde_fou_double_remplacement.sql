-- Garde-fou : empêche la même personne de prendre la place des DEUX
-- participants d'un même Swend (repéré en testant : Kevin renseigné
-- comme personne de confiance à la fois par David et par Eliot sur le
-- même pacte — sans ce garde-fou, il pourrait accepter les deux
-- demandes séparément, puisque la garantie "une seule personne accepte"
-- de repondre_demande_remplacement() ne s'appliquait jusque-là qu'à
-- l'intérieur d'un même côté).
--
-- Remplace intégralement la fonction existante (même nom, même
-- signature) — sûr à ré-exécuter, `create or replace`.

create or replace function repondre_demande_remplacement(
  p_remplacant_id uuid,
  p_accepte boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_pacte_id uuid;
  v_cote text;
  v_demande_statut text;
  v_deja_pris boolean;
  v_deja_remplacant_autre_cote boolean;
begin
  select pacte_id, cote, demande_statut
    into v_pacte_id, v_cote, v_demande_statut
  from remplacants
  where id = p_remplacant_id
    and profil_id = v_uid;

  if not found then
    raise exception 'Non autorisé';
  end if;

  if v_demande_statut is distinct from 'envoyee' then
    raise exception 'demande_non_active';
  end if;

  if not p_accepte then
    update remplacants set demande_statut = 'refusee' where id = p_remplacant_id;
    return;
  end if;

  -- Verrouille toutes les fiches remplaçants du pacte, DES DEUX côtés
  -- cette fois (pas seulement celui de la demande) : la garantie
  -- "une seule personne accepte" doit aussi empêcher une même personne
  -- de prendre la place des deux participants à la fois, pas seulement
  -- sérialiser deux acceptations concurrentes du même côté.
  perform 1 from remplacants
    where pacte_id = v_pacte_id
    for update;

  select exists (
    select 1 from remplacants
    where pacte_id = v_pacte_id and cote <> v_cote
      and profil_id = v_uid and selectionne = true
  ) into v_deja_remplacant_autre_cote;

  if v_deja_remplacant_autre_cote then
    raise exception 'deja_remplacant_autre_cote';
  end if;

  select exists (
    select 1 from remplacants
    where pacte_id = v_pacte_id and cote = v_cote and selectionne = true
  ) into v_deja_pris;

  if v_deja_pris then
    update remplacants set demande_statut = 'cloturee'
      where id = p_remplacant_id and demande_statut = 'envoyee';
    raise exception 'place_deja_prise';
  end if;

  update remplacants
    set selectionne = true, demande_statut = 'acceptee'
    where id = p_remplacant_id;

  update remplacants
    set demande_statut = 'cloturee'
    where pacte_id = v_pacte_id and cote = v_cote
      and id <> p_remplacant_id
      and demande_statut = 'envoyee';
end;
$$;

grant execute on function repondre_demande_remplacement(uuid, boolean) to authenticated;
