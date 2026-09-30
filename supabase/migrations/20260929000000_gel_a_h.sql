-- Migration : gel à l'heure du Swend (D-023a — Gel à H).
-- À exécuter après annulation_manuelle.sql. Sûre à ré-exécuter.
--
-- Règle : à l'heure prévue du Swend (pactes.date_retenue, heure du serveur,
-- jamais celle de l'appareil), l'état du rendez-vous est figé. On ne gère
-- plus l'imprévu ; on entre dans l'après-Swend (chat post-Swend : D-023b,
-- NON implémenté ici).
--
-- Contenu :
--  1. Toutes les actions d'imprévu refusées dès date_retenue <= now()
--     (erreur métier `swend_passe`) : demander, annuler une demande,
--     accepter / refuser, se désister, ajouter et demander, signaler
--     (in)disponibilité, ajouter ou retirer une personne de confiance.
--     L'annulation du Swend l'était déjà (annuler_swend, D-022).
--  2. Retirer une personne ne détruit plus rien : la fiche est archivée
--     (remplacants.retire_le), sa conversation et ses événements restent en
--     base ; elle disparaît des listes et la personne n'a plus accès au Swend.
--  2 bis. Accès des personnes de confiance (fonctions versionnées et
--     politiques RESTRICTIVES, sans toucher à est_remplacant_du_pacte(), qui
--     existe en production sans être versionnée) : avant H, sur un Swend en
--     cours, une personne de confiance non retirée garde les accès de son
--     rôle ; une fois le Swend passé ou annulé, seul le remplaçant
--     sélectionné garde l'accès au Swend, à sa fiche et à sa conversation ;
--     une personne retirée n'a plus accès. Les titulaires gardent toujours le
--     Swend et toutes les conversations de leur côté (données conservées).
--  3. Conversations de l'imprévu en lecture seule : dès H, et dès qu'un
--     Swend est annulé (ou annulé pour double remplacement). Lecture et
--     historique conservés, aucun nouveau message.
--  4. Moteur figer_swends_passes(p_maintenant) (pg_cron, planification à
--     part — voir supabase/planification/gel_a_h_pg_cron.sql) : à H, clôture
--     silencieuse des demandes encore en attente, push « La demande n’est
--     plus d’actualité / L’heure du Swend est passée. » aux personnes
--     sollicitées (une seule par personne), événement de fin « Le Swend a
--     commencé » dans les conversations ayant eu une activité. Idempotent,
--     sûr en concurrence (mêmes verrous que les autres fonctions), anti-
--     doublon persistant (swends_figes).
--  5. Rattrapage : les Swends dont l'heure est déjà passée à l'exécution de
--     cette migration sont marqués « déjà traités » (aucune push, aucun
--     événement, aucune clôture rétroactive).
--  6. destination_rappel() : après H, jamais « Un imprévu ? ».
--  7. Un Swend ne peut jamais être scellé si sa date est passée, et la date
--     d'un Swend scellé n'est plus modifiable par l'app.
--
-- Hors scope (D-023b / D-023c) : aucun chat post-Swend, aucune table de
-- participants, aucune notification « Alors, ce Swend ? ». Le statut reste
-- `confirme` après H (« passé » est dérivé de date_retenue) : aucun
-- indicateur du profil n'est modifié.

-- 0. Fiches archivées ----------------------------------------------------------
-- NULL = fiche active. Posée uniquement par retirer_remplacant() (l'app n'a
-- aucun droit UPDATE sur remplacants ; à l'insertion elle est forcée à NULL).

alter table public.remplacants add column if not exists retire_le timestamptz;

-- Une personne retirée peut être ajoutée à nouveau (nouvelle fiche) : l'unicité
-- « une fois par côté » ne porte que sur les fiches actives.
drop index if exists public.remplacants_personne_unique_par_cote;
create unique index remplacants_personne_unique_par_cote
  on public.remplacants (pacte_id, cote, telephone_e164)
  where telephone_e164 is not null and retire_le is null;

-- 0 bis. Accès d'une personne de confiance ---------------------------------------
-- Règle (D-023a) : une fiche donne accès à la personne elle-même si elle
-- n'est pas retirée ET (le Swend est en cours — ni annulé, ni passé — OU
-- elle est le remplaçant sélectionné). Donc après H ou après annulation,
-- seul le remplaçant sélectionné garde l'accès ; les personnes seulement
-- prévues, sollicitées, ayant refusé ou désistées le perdent (données
-- conservées). La condition « Swend scellé » (D-019) reste appliquée par
-- ailleurs. SECURITY DEFINER : lecture sans RLS, pour éviter toute récursion
-- entre les politiques de pactes et de remplacants.

create or replace function public.fiche_de_confiance_accessible(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and r.retire_le is null
      and (r.selectionne
           or (p.statut not in ('annule', 'annuleDoubleAbsence', 'maintenu')
               and (p.date_retenue is null or p.date_retenue > now()))))
$$;

-- L'utilisateur connecté a une fiche accessible sur ce Swend.
create or replace function public.personne_de_confiance_a_acces(p_pacte_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from remplacants r
    where r.pacte_id = p_pacte_id and r.profil_id = auth.uid()
      and public.fiche_de_confiance_accessible(r.id))
$$;

-- Une conversation (fiche) est lisible par le titulaire de ce côté, ou par
-- la personne de confiance elle-même si sa fiche lui est accessible.
create or replace function public.fil_lisible(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and ((r.cote = 'initiateur' and p.initiateur_id = auth.uid())
        or (r.cote = 'destinataire' and p.destinataire_id = auth.uid())
        or (r.profil_id = auth.uid() and public.fiche_de_confiance_accessible(r.id))))
$$;

revoke execute on function public.fiche_de_confiance_accessible(uuid) from public, anon;
revoke execute on function public.personne_de_confiance_a_acces(uuid) from public, anon;
revoke execute on function public.fil_lisible(uuid) from public, anon;
grant execute on function public.fiche_de_confiance_accessible(uuid) to authenticated;
grant execute on function public.personne_de_confiance_a_acces(uuid) to authenticated;
grant execute on function public.fil_lisible(uuid) to authenticated;

-- Politiques RESTRICTIVES (combinées en ET avec les politiques existantes,
-- quelles qu'elles soient, sans dépendre de leur nom ni de leur définition).
-- Les titulaires ne sont jamais concernés.
drop policy if exists pactes_acces_personne_de_confiance on public.pactes;
create policy pactes_acces_personne_de_confiance on public.pactes
  as restrictive for select to authenticated
  using (initiateur_id = auth.uid() or destinataire_id = auth.uid()
         or public.personne_de_confiance_a_acces(id));

drop policy if exists remplacants_tiers_non_retire on public.remplacants;
drop policy if exists remplacants_acces_personne_de_confiance on public.remplacants;
create policy remplacants_acces_personne_de_confiance on public.remplacants
  as restrictive for select to authenticated
  using (profil_id is null or profil_id <> auth.uid()
         or public.fiche_de_confiance_accessible(id));

drop policy if exists evenements_fil_lecture_autorisee on public.evenements_fil;
create policy evenements_fil_lecture_autorisee on public.evenements_fil
  as restrictive for select to authenticated
  using (public.fil_lisible(remplacant_id));

-- État d'un côté pour les rappels (D-021) : une fiche retirée ne compte plus
-- (comme avant, quand elle était supprimée).
create or replace function public.etat_cote_titulaire(p_pacte_id uuid, p_cote text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (select 1 from remplacants
                 where pacte_id = p_pacte_id and cote = p_cote and selectionne) then 'remplace'
    when exists (select 1 from remplacants
                 where pacte_id = p_pacte_id and cote = p_cote and retire_le is null
                   and demande_statut in ('envoyee', 'refusee', 'desistee')) then 'cherche'
    else 'normal'
  end
$$;

-- 1. Nouvelle fiche : jamais après H --------------------------------------------
-- Identique à telephones_phase2.sql, plus : refus après H pour un appel de
-- l'app (auth.uid() renseigné — les insertions internes, sans utilisateur,
-- ne sont pas concernées), fiche toujours active à la naissance, doublons
-- vérifiés parmi les fiches actives seulement.

create or replace function public.normaliser_nouveau_remplacant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e164 text := public.normaliser_telephone(new.telephone);
  v_pacte pactes%rowtype;
begin
  select * into v_pacte from pactes where id = new.pacte_id for update;

  if auth.uid() is not null and v_pacte.date_retenue is not null
     and v_pacte.date_retenue <= now() then
    raise exception 'swend_passe';
  end if;

  new.selectionne := false;
  new.demande_statut := null;
  new.retire_le := null;

  if v_e164 is null then
    raise exception 'telephone_invalide';
  end if;

  new.profil_id := (select id from profiles where telephone_e164 = v_e164);

  if new.profil_id is not null
       and (new.profil_id = v_pacte.initiateur_id or new.profil_id = v_pacte.destinataire_id)
     or v_e164 = v_pacte.destinataire_telephone_e164
     or v_e164 = (select telephone_e164 from profiles where id = v_pacte.initiateur_id) then
    raise exception 'personne_est_participant';
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = new.pacte_id and cote = new.cote and telephone_e164 = v_e164
      and retire_le is null
  ) then
    raise exception 'personne_deja_prevue';
  end if;

  if new.profil_id is not null and exists (
    select 1 from remplacants
    where pacte_id = new.pacte_id and cote <> new.cote
      and profil_id = new.profil_id and selectionne = true
  ) then
    new.demande_statut := 'cloturee';
  end if;

  return new;
end;
$$;

-- 2. Actions d'imprévu : refus après H -------------------------------------------
-- Chaque fonction garde sa logique (versions précédentes : un_imprevu_v2.sql,
-- disponibilite_spontanee_et_notifications.sql, scellage_et_negociation.sql)
-- et vérifie l'heure juste après avoir verrouillé le Swend, avant tout
-- contrôle de la fiche : après H, la réponse est toujours `swend_passe`
-- (même si le moteur a déjà clôturé la demande). now() = début de la
-- transaction, identique pour toute la fonction.

create or replace function public.envoyer_demande_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes
  where id = v_fiche.pacte_id
    and ((v_fiche.cote = 'initiateur' and initiateur_id = v_uid)
      or (v_fiche.cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;
  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_fiche.retire_le is not null then
    raise exception 'demande_non_active';
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote and selectionne = true
  ) then
    raise exception 'place_deja_prise';
  end if;

  if v_fiche.selectionne or v_fiche.demande_statut is not null
     or v_fiche.indisponible_spontanement then
    raise exception 'personne_indisponible';
  end if;

  if v_fiche.profil_id is not null and exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote
      and profil_id = v_fiche.profil_id and selectionne = true
  ) then
    raise exception 'personne_indisponible';
  end if;

  update remplacants set demande_statut = 'envoyee' where id = p_remplacant_id;
end;
$$;

create or replace function public.annuler_demande_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select date_retenue into v_date from pactes
  where id = v_fiche.pacte_id
    and ((v_fiche.cote = 'initiateur' and initiateur_id = v_uid)
      or (v_fiche.cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_fiche.selectionne or v_fiche.demande_statut = 'acceptee' then
    raise exception 'deja_acceptee';
  end if;
  if v_fiche.demande_statut is distinct from 'envoyee' then
    raise exception 'demande_non_active';
  end if;

  update remplacants set demande_statut = null where id = p_remplacant_id;
end;
$$;

create or replace function public.repondre_demande_remplacement(
  p_remplacant_id uuid,
  p_accepte boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  if v_fiche.demande_statut is distinct from 'envoyee' then
    if v_fiche.demande_statut = 'cloturee' then
      raise exception 'place_deja_prise';
    end if;
    raise exception 'demande_non_active';
  end if;

  if not p_accepte then
    update remplacants set demande_statut = 'refusee' where id = p_remplacant_id;
    return;
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote
      and profil_id = v_uid and selectionne = true
  ) then
    raise exception 'deja_remplacant_autre_cote';
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote and selectionne = true
  ) then
    raise exception 'place_deja_prise';
  end if;

  update remplacants
    set selectionne = true, demande_statut = 'acceptee'
    where id = p_remplacant_id;

  update remplacants
    set demande_statut = 'cloturee'
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote
      and id <> p_remplacant_id
      and demande_statut = 'envoyee';

  update remplacants
    set demande_statut = 'cloturee'
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote
      and profil_id = v_uid and retire_le is null
      and (demande_statut is null or demande_statut = 'envoyee');
end;
$$;

create or replace function public.se_desister_du_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;
  if not v_fiche.selectionne or v_fiche.demande_statut is distinct from 'acceptee' then
    raise exception 'demande_non_active';
  end if;

  update remplacants
    set selectionne = false, demande_statut = 'desistee'
    where id = p_remplacant_id;

  update remplacants r
    set demande_statut = null
    where r.pacte_id = v_fiche.pacte_id and r.cote = v_fiche.cote
      and r.demande_statut = 'cloturee' and r.retire_le is null
      and not (r.profil_id is not null and exists (
        select 1 from remplacants o
        where o.pacte_id = r.pacte_id and o.cote <> r.cote
          and o.profil_id = r.profil_id and o.selectionne = true));

  update remplacants r
    set demande_statut = null
    where r.pacte_id = v_fiche.pacte_id and r.cote <> v_fiche.cote
      and r.profil_id = v_uid and r.retire_le is null
      and r.demande_statut = 'cloturee'
      and not exists (
        select 1 from remplacants o
        where o.pacte_id = r.pacte_id and o.cote = r.cote and o.selectionne = true);
end;
$$;

-- Retirer : même règle qu'avant (impossible si demande en attente ou place
-- prise), mais plus rien n'est détruit — la fiche est archivée, sa
-- conversation et ses événements sont conservés. Refusé après H.
create or replace function public.retirer_remplacant(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select date_retenue into v_date from pactes
  where id = v_fiche.pacte_id
    and ((v_fiche.cote = 'initiateur' and initiateur_id = v_uid)
      or (v_fiche.cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_fiche.retire_le is not null then
    return;
  end if;
  if v_fiche.selectionne or v_fiche.demande_statut in ('envoyee', 'acceptee') then
    raise exception 'retrait_impossible';
  end if;

  update remplacants set retire_le = clock_timestamp() where id = p_remplacant_id;
end;
$$;

create or replace function public.ajouter_et_demander_remplacement(
  p_pacte_id uuid,
  p_cote text,
  p_prenom text,
  p_nom text,
  p_telephone text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_statut text;
  v_date timestamptz;
  v_id uuid;
  v_demande text;
begin
  if coalesce(trim(p_prenom), '') = '' or coalesce(trim(p_nom), '') = ''
     or coalesce(trim(p_telephone), '') = '' then
    raise exception 'champs_manquants';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes
  where id = p_pacte_id
    and ((p_cote = 'initiateur' and initiateur_id = v_uid)
      or (p_cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;
  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = p_pacte_id for update;

  if exists (
    select 1 from remplacants
    where pacte_id = p_pacte_id and cote = p_cote and selectionne = true
  ) then
    raise exception 'place_deja_prise';
  end if;

  insert into remplacants (pacte_id, cote, prenom, nom, telephone, email)
  values (p_pacte_id, p_cote, trim(p_prenom), trim(p_nom), trim(p_telephone), '')
  returning id, demande_statut into v_id, v_demande;

  if v_demande is not null then
    raise exception 'personne_indisponible';
  end if;

  update remplacants set demande_statut = 'envoyee' where id = v_id;
  return v_id;
end;
$$;

create or replace function public.signaler_indisponibilite(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_scelle timestamptz;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid and retire_le is null;
  if not found or v_uid is null then
    raise exception 'Non autorisé';
  end if;

  select statut, scelle_le, date_retenue into v_statut, v_scelle, v_date
  from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_scelle is null or v_statut in ('annule', 'annuleDoubleAbsence', 'maintenu') then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;
  if v_fiche.indisponible_spontanement then
    return;
  end if;
  if v_fiche.selectionne or v_fiche.demande_statut is not null then
    raise exception 'demande_non_active';
  end if;

  update remplacants set indisponible_spontanement = true where id = p_remplacant_id;
end;
$$;

create or replace function public.signaler_disponibilite(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_scelle timestamptz;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid and retire_le is null;
  if not found or v_uid is null then
    raise exception 'Non autorisé';
  end if;

  select statut, scelle_le, date_retenue into v_statut, v_scelle, v_date
  from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_scelle is null or v_statut in ('annule', 'annuleDoubleAbsence', 'maintenu') then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;
  if not v_fiche.indisponible_spontanement then
    return;
  end if;

  update remplacants set indisponible_spontanement = false where id = p_remplacant_id;
end;
$$;

-- 3. Conversations de l'imprévu : lecture seule après H ou annulation ------------
-- Lecture : Swend scellé (fil_est_actif, D-019) et conversation lisible par
-- l'appelant (fil_lisible, voir 0 bis). Écriture (nouveau
-- message, et toute modification) : seulement tant que le Swend est scellé,
-- toujours `confirme`, avant son heure, et la fiche active. Le contrôle se
-- fait dans la transaction du message : un message commencé avant H passe,
-- un message commencé à H ou après est refusé.

create or replace function public.fil_ecriture_ouverte(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and r.retire_le is null
      and p.scelle_le is not null
      and p.statut = 'confirme'
      and (p.date_retenue is null or p.date_retenue > now()))
$$;
revoke execute on function public.fil_ecriture_ouverte(uuid) from public, anon;
grant execute on function public.fil_ecriture_ouverte(uuid) to authenticated;

drop policy if exists messages_apres_scellage on public.messages;
drop policy if exists messages_lecture_apres_scellage on public.messages;
drop policy if exists messages_ecriture_ouverte on public.messages;
drop policy if exists messages_modification_ouverte on public.messages;
drop policy if exists messages_suppression_ouverte on public.messages;

create policy messages_lecture_apres_scellage on public.messages
  as restrictive for select to authenticated
  using (public.fil_est_actif(remplacant_id) and public.fil_lisible(remplacant_id));
create policy messages_ecriture_ouverte on public.messages
  as restrictive for insert to authenticated
  with check (public.fil_ecriture_ouverte(remplacant_id));
create policy messages_modification_ouverte on public.messages
  as restrictive for update to authenticated
  using (public.fil_ecriture_ouverte(remplacant_id))
  with check (public.fil_ecriture_ouverte(remplacant_id));
create policy messages_suppression_ouverte on public.messages
  as restrictive for delete to authenticated
  using (public.fil_ecriture_ouverte(remplacant_id));

-- 4. Événement de fin ----------------------------------------------------------

alter table public.evenements_fil drop constraint if exists evenements_fil_code_check;
alter table public.evenements_fil add constraint evenements_fil_code_check check (code in (
  'demande_envoyee', 'demande_annulee', 'demande_refusee', 'demande_acceptee',
  'desistement', 'demande_cloturee',
  'indisponibilite_signalee', 'disponibilite_retablie',
  'swend_commence'   -- à H (moteur figer_swends_passes) : conversation terminée
));

-- 5. Pas de push parasite pendant le gel ---------------------------------------
-- Identique à annulation_manuelle.sql, plus le silence pendant
-- figer_swends_passes() (réglage de transaction swend.gel_en_cours) : la
-- clôture d'une demande à H n'envoie jamais « C'est bon, quelqu'un a pu
-- prendre la place » (le moteur envoie lui-même la push validée).

create or replace function public.notifier_demande_remplacement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_titulaire_id uuid;
  v_titulaire_nom text;
  v_titulaire_prenom text;
  v_personne text := coalesce(nullif(trim(new.prenom), ''), 'Une personne de confiance');
  v_nom_personne text := trim(coalesce(new.prenom, '') || ' ' || coalesce(new.nom, ''));
  v_corps text;
begin
  if new.profil_id is null then
    return new;
  end if;
  -- Annulation manuelle (D-022) ou gel à H (D-023a) : la fonction appelante
  -- envoie elle-même les push validées ; aucune autre ici.
  if coalesce(current_setting('swend.annulation_en_cours', true), 'off') = 'on'
     or coalesce(current_setting('swend.gel_en_cours', true), 'off') = 'on' then
    return new;
  end if;

  select case when new.cote = 'initiateur' then initiateur_id else destinataire_id end,
         case when new.cote = 'initiateur' then initiateur_nom else destinataire_nom end
    into v_titulaire_id, v_titulaire_nom
    from pactes where id = new.pacte_id;
  v_titulaire_prenom := coalesce(nullif(split_part(trim(v_titulaire_nom), ' ', 1), ''), 'Ton contact');

  -- Indisponibilité spontanée : la personne → son titulaire.
  if new.indisponible_spontanement is distinct from old.indisponible_spontanement then
    if v_titulaire_id is not null then
      perform notifier(
        v_titulaire_id,
        'Swend',
        v_personne || case when new.indisponible_spontanement
          then ' ne sera pas disponible en cas d''imprévu pour ce Swend.'
          else ' est de nouveau disponible en cas d''imprévu pour ce Swend.' end,
        jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', v_nom_personne)
      );
    end if;
    return new;
  end if;

  if new.demande_statut is not distinct from old.demande_statut then
    return new;
  end if;

  if new.demande_statut = 'envoyee' then
    perform notifier(
      new.profil_id,
      'On a besoin de toi',
      coalesce(v_titulaire_nom, 'Quelqu''un') || ' te demande de prendre sa place pour un Swend.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  elsif new.demande_statut = 'cloturee' and old.demande_statut = 'envoyee' then
    if exists (
      select 1 from remplacants
      where pacte_id = new.pacte_id and cote <> new.cote
        and profil_id = new.profil_id and selectionne = true
    ) then
      return new;
    end if;
    perform notifier(
      new.profil_id,
      'Swend',
      'C''est bon, quelqu''un a pu prendre la place.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  -- Annulation par le titulaire → la personne sollicitée.
  elsif new.demande_statut is null and old.demande_statut = 'envoyee' then
    perform notifier(
      new.profil_id,
      'Swend',
      v_titulaire_prenom || ' a annulé sa demande.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  -- Réponses et désistement de la personne → son titulaire.
  elsif v_titulaire_id is not null and (
        (old.demande_statut = 'envoyee' and new.demande_statut in ('acceptee', 'refusee'))
     or (old.demande_statut = 'acceptee' and new.demande_statut = 'desistee')) then
    if new.demande_statut = 'acceptee' and exists (
      select 1 from remplacants
      where pacte_id = new.pacte_id and cote <> new.cote and selectionne = true
    ) then
      return new;
    end if;
    v_corps := case new.demande_statut
      when 'acceptee' then v_personne || ' a accepté de prendre votre place.'
      when 'refusee' then v_personne || ' ne peut pas prendre votre place.'
      else v_personne || ' ne peut finalement plus prendre votre place.'
    end;
    perform notifier(
      v_titulaire_id,
      'Swend',
      v_corps,
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', v_nom_personne)
    );
  end if;

  return new;
end;
$$;

-- 6. Moteur du gel à H -----------------------------------------------------------
-- Une ligne par Swend traité (ou marqué traité par le rattrapage) : jamais
-- traité deux fois, même si le moteur tourne en parallèle.

create table if not exists public.swends_figes (
  pacte_id uuid primary key references public.pactes(id) on delete cascade,
  date_retenue timestamptz not null,
  fige_le timestamptz not null default clock_timestamp(),
  rattrapage boolean not null default false
);
alter table public.swends_figes enable row level security;
revoke all on table public.swends_figes from public, anon, authenticated;

-- Rattrapage : Swends scellés dont l'heure est déjà passée à l'exécution de
-- cette migration = déjà traités (aucune push, aucun événement, aucune
-- clôture). Ré-exécutée plus tard, elle ne marque que les Swends passés pas
-- encore traités par le moteur (au plus quelques minutes de retard).
create or replace function public.rattraper_swends_figes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  insert into swends_figes (pacte_id, date_retenue, rattrapage)
  select id, date_retenue, true from pactes
  where scelle_le is not null and date_retenue is not null and date_retenue <= now()
  on conflict (pacte_id) do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.rattraper_swends_figes() from public, anon, authenticated;
select public.rattraper_swends_figes();

-- Le moteur, appelé toutes les 5 minutes par pg_cron (et, dans le banc QA,
-- avec un instant contrôlé). Pour chaque Swend `confirme` dont l'heure est
-- atteinte et pas encore traité :
--  * verrouille le Swend puis toutes ses fiches (même ordre que les autres
--    fonctions : une acceptation en cours se termine avant, ou échoue après) ;
--  * clôt les demandes encore en attente (événement « La demande n'est plus
--    d'actualité » par le déclencheur existant), sans push parasite ;
--  * push validée aux personnes sollicitées ayant un compte, une seule par
--    personne (même personne des deux côtés), seulement dans les 12 heures
--    qui suivent l'heure du Swend (après une longue panne du planificateur,
--    l'état est corrigé sans push tardive) ;
--  * événement de fin dans chaque conversation active ayant eu une activité
--    (un message ou un événement) ; une conversation vierge reste vierge.
-- Le titulaire qui cherchait ne reçoit rien de spécifique.

create or replace function public.figer_swends_passes(p_maintenant timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fenetre_push constant interval := interval '12 hours';
  p record;
  v_statut text;
  v_date timestamptz;
  v_initiateur_nom text;
  v_destinataire_nom text;
  v_cloturees uuid[];
  v_fiche record;
  n integer := 0;
begin
  for p in
    select pa.id from pactes pa
    where pa.statut = 'confirme'
      and pa.scelle_le is not null
      and pa.date_retenue is not null
      and pa.date_retenue <= p_maintenant
      and not exists (select 1 from swends_figes f where f.pacte_id = pa.id)
    order by pa.date_retenue, pa.id
  loop
    select statut, date_retenue, initiateur_nom, destinataire_nom
      into v_statut, v_date, v_initiateur_nom, v_destinataire_nom
    from pactes where id = p.id for update;
    perform 1 from remplacants where pacte_id = p.id for update;
    continue when v_statut is distinct from 'confirme' or v_date > p_maintenant;

    insert into swends_figes (pacte_id, date_retenue) values (p.id, v_date)
    on conflict (pacte_id) do nothing;
    continue when not found;

    perform set_config('swend.gel_en_cours', 'on', true);

    with c as (
      update remplacants set demande_statut = 'cloturee'
      where pacte_id = p.id and demande_statut = 'envoyee'
      returning id
    )
    select coalesce(array_agg(id), '{}') into v_cloturees from c;

    if p_maintenant < v_date + c_fenetre_push then
      for v_fiche in
        select distinct on (r.profil_id) r.id, r.cote, r.profil_id
        from remplacants r
        where r.id = any (v_cloturees) and r.profil_id is not null
        order by r.profil_id, r.id
      loop
        -- Au clic : la fiche du Swend si la personne y a encore accès (jamais
        -- après H pour une personne seulement sollicitée : l'app reste alors
        -- sur l'accueil).
        perform notifier(v_fiche.profil_id, 'La demande n’est plus d’actualité',
          'L’heure du Swend est passée.',
          jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
      end loop;
    end if;

    insert into evenements_fil (remplacant_id, code)
    select r.id, 'swend_commence'
    from remplacants r
    where r.pacte_id = p.id and r.retire_le is null
      and (exists (select 1 from messages m where m.remplacant_id = r.id)
           or exists (select 1 from evenements_fil e where e.remplacant_id = r.id))
    order by r.id;

    perform set_config('swend.gel_en_cours', 'off', true);
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.figer_swends_passes(timestamptz) from public, anon, authenticated;

-- 7. Rappel cliqué après H : jamais « Un imprévu ? » -------------------------------

create or replace function public.destination_rappel(p_pacte_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  p pactes%rowtype;
  v_cote text;
begin
  select * into p from pactes where id = p_pacte_id;
  if not found or v_uid is null then
    return null;
  end if;
  v_cote := case when p.initiateur_id = v_uid then 'initiateur'
                 when p.destinataire_id = v_uid then 'destinataire' end;
  if v_cote is not null then
    if p.statut = 'confirme' and (p.date_retenue is null or p.date_retenue > now())
       and etat_cote_titulaire(p.id, v_cote) = 'cherche' then
      return 'imprevu';
    end if;
    return 'fiche';
  end if;
  if exists (select 1 from remplacants r
             where r.pacte_id = p.id and r.profil_id = v_uid and r.selectionne) then
    return 'fiche';
  end if;
  return null;
end;
$$;

-- 8. Scellement et date d'un Swend scellé ----------------------------------------
-- Pour l'app (authenticated / anon) : un Swend ne peut jamais devenir
-- `confirme` si sa date est déjà passée (erreur `swend_passe`), et la date
-- d'un Swend scellé ne peut plus changer (`modification_interdite`, elle
-- rouvrirait l'imprévu après H). Les Swends existants ne sont pas modifiés ;
-- les fonctions serveur, le service role et le SQL Editor ne sont pas
-- concernés.

create or replace function public.proteger_date_scellement()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.scelle_le is not null
     and new.date_retenue is distinct from old.date_retenue then
    raise exception 'modification_interdite';
  end if;
  if new.statut = 'confirme'
     and (tg_op = 'INSERT' or old.statut is distinct from 'confirme')
     and new.date_retenue is not null and new.date_retenue <= now() then
    raise exception 'swend_passe';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_date_scellement on public.pactes;
create trigger trg_proteger_date_scellement
  before insert or update on public.pactes
  for each row execute function public.proteger_date_scellement();

-- Vérification (résultat affiché) ------------------------------------------
select 'Fiches archivées (retire_le) et unicité sur les fiches actives' as verification,
  (exists (select 1 from information_schema.columns where table_schema = 'public'
           and table_name = 'remplacants' and column_name = 'retire_le')
   and (select pg_get_indexdef(indexrelid) like '%retire_le IS NULL%' from pg_index
        where indexrelid = 'public.remplacants_personne_unique_par_cote'::regclass))::text as resultat
union all
select 'Actions d''imprévu refusées après H (8 fonctions + ajout d''une personne)',
  ((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosrc like '%swend_passe%'
      and p.proname in ('envoyer_demande_remplacement', 'annuler_demande_remplacement',
        'repondre_demande_remplacement', 'se_desister_du_remplacement', 'retirer_remplacant',
        'ajouter_et_demander_remplacement', 'signaler_indisponibilite', 'signaler_disponibilite',
        'normaliser_nouveau_remplacant')) = 9)::text
union all
select 'Accès des personnes de confiance : Swend, fiche, événements (politiques restrictives)',
  ((select count(*) from pg_policies where schemaname = 'public' and permissive = 'RESTRICTIVE'
      and policyname in ('pactes_acces_personne_de_confiance', 'remplacants_acces_personne_de_confiance',
                         'evenements_fil_lecture_autorisee')) = 3
   and to_regprocedure('public.personne_de_confiance_a_acces(uuid)') is not null
   and to_regprocedure('public.fiche_de_confiance_accessible(uuid)') is not null
   and to_regprocedure('public.fil_lisible(uuid)') is not null)::text
union all
select 'Retirer une personne ne supprime plus rien',
  (select prosrc not like '%delete from%' and prosrc like '%retire_le = clock_timestamp()%'
   from pg_proc where oid = 'public.retirer_remplacant(uuid)'::regprocedure)::text
union all
select 'Conversations : écriture fermée après H ou annulation (politiques restrictives)',
  ((select count(*) from pg_policies where schemaname = 'public' and tablename = 'messages'
      and permissive = 'RESTRICTIVE'
      and policyname in ('messages_lecture_apres_scellage', 'messages_ecriture_ouverte',
                         'messages_modification_ouverte', 'messages_suppression_ouverte')) = 4
   and not exists (select 1 from pg_policies where schemaname = 'public'
                   and policyname = 'messages_apres_scellage')
   and (select qual like '%fil_lisible%' from pg_policies where schemaname = 'public'
        and policyname = 'messages_lecture_apres_scellage'))::text
union all
select 'Moteur du gel en place, réservé au serveur',
  (to_regprocedure('public.figer_swends_passes(timestamptz)') is not null
   and not has_function_privilege('authenticated', 'public.figer_swends_passes(timestamptz)', 'execute')
   and not has_table_privilege('authenticated', 'public.swends_figes', 'select'))::text
union all
select 'Rattrapage : tous les Swends déjà passés sont marqués traités',
  (not exists (select 1 from public.pactes p
               where p.scelle_le is not null and p.date_retenue <= now()
                 and not exists (select 1 from public.swends_figes f where f.pacte_id = p.id)))::text
union all
select 'Pas de push parasite pendant le gel',
  (select prosrc like '%swend.gel_en_cours%' from pg_proc
   where oid = 'public.notifier_demande_remplacement()'::regprocedure)::text
union all
select 'Scellement après la date refusé, date d''un Swend scellé figée',
  exists (select 1 from pg_trigger where not tgisinternal and tgname = 'trg_proteger_date_scellement')::text;
