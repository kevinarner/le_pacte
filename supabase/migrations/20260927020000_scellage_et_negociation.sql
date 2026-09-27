-- Migration : personnes de confiance actives seulement après scellage
-- (D-019) et limite de négociation de date garantie par la base (D-011).
-- À exécuter après disponibilite_spontanee_et_notifications.sql.
-- Sûre à ré-exécuter.
--
-- Données : ajoute pactes.scelle_le et le remplit pour les Swends déjà
-- scellés (voir 2). Aucune autre donnée modifiée.
--
-- D-019 — Avant le scellage, une personne de confiance déjà rattachée à
-- son compte (profil_id) voyait le Swend : RLS de `pactes` via
-- est_remplacant_du_pacte(), sa fiche `remplacants` (profil_id = moi),
-- donc "On compte sur toi", la fiche du Swend et la conversation. Désormais
-- toute lecture côté personne de confiance exige un Swend scellé, par des
-- politiques RESTRICTIVES (combinées en ET avec les politiques existantes,
-- sans dépendre de leur nom). Une conversation n'existe qu'après scellage
-- (aucun message, donc aucune notification de message, avant).
--
-- D-011 — Après la proposition initiale : au plus 2 contre-propositions AU
-- TOTAL (les deux titulaires confondus). Déjà respecté par l'app ; la base
-- le garantit désormais (erreur `negociation_terminee`).

-- 1. Date de scellage ------------------------------------------------------

alter table public.pactes add column if not exists scelle_le timestamptz;

-- 2. Rattrapage des Swends existants --------------------------------------
-- Scellé = passé par `confirme` : confirme, maintenu, annuleDoubleAbsence ;
-- et `annule` si le destinataire avait accepté (il renseigne ses personnes
-- de confiance au moment d'accepter), pour qu'un Swend scellé puis annulé
-- reste visible de ses personnes de confiance. Un refus ou une négociation
-- abandonnée n'a jamais été scellé.

create or replace function public.rattraper_scellement()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  -- Le déclencheur trg_marquer_scellement protège scelle_le : on le
  -- signale explicitement pour ce seul rattrapage (limité à la transaction).
  perform set_config('swend.rattrapage_scellement', 'on', true);
  update pactes p set scelle_le = coalesce(p.date_retenue, now())
  where p.scelle_le is null
    and (p.statut in ('confirme', 'maintenu', 'annuleDoubleAbsence')
         or (p.statut = 'annule' and exists (
               select 1 from remplacants r where r.pacte_id = p.id and r.cote = 'destinataire')));
  get diagnostics n = row_count;
  perform set_config('swend.rattrapage_scellement', 'off', true);
  return n;
end;
$$;
revoke execute on function public.rattraper_scellement() from public, anon, authenticated;

drop trigger if exists trg_marquer_scellement on public.pactes;
select public.rattraper_scellement();

-- 3. La date de scellage n'est posée que par la base -----------------------

create or replace function public.marquer_scellement()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.scelle_le := case when new.statut = 'confirme' then clock_timestamp() end;
  elsif coalesce(current_setting('swend.rattrapage_scellement', true), 'off') <> 'on' then
    new.scelle_le := old.scelle_le; -- jamais modifiable par l'app
  end if;
  if tg_op = 'UPDATE' and new.statut = 'confirme' and new.scelle_le is null then
    new.scelle_le := clock_timestamp();
  end if;
  return new;
end;
$$;

create trigger trg_marquer_scellement
  before insert or update on public.pactes
  for each row execute function public.marquer_scellement();

create or replace function public.pacte_est_scelle(p_pacte_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from pactes where id = p_pacte_id and scelle_le is not null)
$$;

create or replace function public.fil_est_actif(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id and p.scelle_le is not null)
$$;

revoke execute on function public.pacte_est_scelle(uuid) from public, anon;
revoke execute on function public.fil_est_actif(uuid) from public, anon;
grant execute on function public.pacte_est_scelle(uuid) to authenticated;
grant execute on function public.fil_est_actif(uuid) to authenticated;

-- 4. Politiques restrictives (D-019) ---------------------------------------

-- Un Swend n'est lisible que par ses titulaires tant qu'il n'est pas scellé.
drop policy if exists pactes_tiers_apres_scellage on public.pactes;
create policy pactes_tiers_apres_scellage on public.pactes
  as restrictive for select to authenticated
  using (initiateur_id = auth.uid() or destinataire_id = auth.uid() or scelle_le is not null);

-- Une personne de confiance ne lit sa propre fiche qu'une fois le Swend scellé
-- (le titulaire, lui, voit toujours sa liste).
drop policy if exists remplacants_tiers_apres_scellage on public.remplacants;
create policy remplacants_tiers_apres_scellage on public.remplacants
  as restrictive for select to authenticated
  using (profil_id is null or profil_id <> auth.uid() or public.pacte_est_scelle(pacte_id));

-- Pas de conversation avant le scellage : ni lecture, ni écriture (donc
-- aucune notification de message à une personne de confiance).
drop policy if exists messages_apres_scellage on public.messages;
create policy messages_apres_scellage on public.messages
  as restrictive for all to authenticated
  using (public.fil_est_actif(remplacant_id))
  with check (public.fil_est_actif(remplacant_id));

-- 5. Fonctions appelées par la personne de confiance : Swend scellé exigé --

create or replace function public.marquer_fil_lu(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and ((r.profil_id = v_uid and p.scelle_le is not null)
           or (r.cote = 'initiateur' and p.initiateur_id = v_uid)
           or (r.cote = 'destinataire' and p.destinataire_id = v_uid))
  ) then
    raise exception 'Non autorisé';
  end if;
  insert into lectures_fil (remplacant_id, profile_id, lu_le)
  values (p_remplacant_id, v_uid, clock_timestamp())
  on conflict (remplacant_id, profile_id)
  do update set lu_le = greatest(lectures_fil.lu_le, excluded.lu_le);
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
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found or v_uid is null then
    raise exception 'Non autorisé';
  end if;

  select statut, scelle_le into v_statut, v_scelle from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_scelle is null or v_statut in ('annule', 'annuleDoubleAbsence', 'maintenu') then
    raise exception 'swend_inactif';
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
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found or v_uid is null then
    raise exception 'Non autorisé';
  end if;

  select statut, scelle_le into v_statut, v_scelle from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_scelle is null or v_statut in ('annule', 'annuleDoubleAbsence', 'maintenu') then
    raise exception 'swend_inactif';
  end if;
  if not v_fiche.indisponible_spontanement then
    return;
  end if;

  update remplacants set indisponible_spontanement = false where id = p_remplacant_id;
end;
$$;

-- 6. Négociation de date (D-011) -------------------------------------------
-- Toute nouvelle liste de dates (ou tout changement du compteur) est une
-- contre-proposition : seulement pendant la négociation, compteur +1
-- exactement, et au plus 2 au total.

create or replace function public.verifier_negociation_date()
returns trigger
language plpgsql
as $$
begin
  if new.dates_proposees is distinct from old.dates_proposees
     or new.nombre_echanges_date is distinct from old.nombre_echanges_date then
    if old.statut not in ('enAttenteChoixDateDestinataire', 'enAttenteChoixDateInitiateur')
       or new.nombre_echanges_date is distinct from old.nombre_echanges_date + 1
       or new.nombre_echanges_date > 2 then
      raise exception 'negociation_terminee';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_verifier_negociation_date on public.pactes;
create trigger trg_verifier_negociation_date
  before update of dates_proposees, nombre_echanges_date on public.pactes
  for each row execute function public.verifier_negociation_date();

-- Vérification (résultat affiché) ------------------------------------------
select 'Colonne scelle_le présente' as verification,
  exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'pactes' and column_name = 'scelle_le')::text as resultat
union all
select 'Tous les Swends scellés ont une date de scellage',
  (not exists (select 1 from public.pactes
               where statut in ('confirme', 'maintenu', 'annuleDoubleAbsence') and scelle_le is null))::text
union all
select 'Politiques restrictives en place (Swend, fiche, conversation)',
  ((select count(*) from pg_policies where schemaname = 'public' and permissive = 'RESTRICTIVE'
      and policyname in ('pactes_tiers_apres_scellage', 'remplacants_tiers_apres_scellage', 'messages_apres_scellage')) = 3)::text
union all
select 'Déclencheurs en place (scellage, négociation)',
  ((select count(*) from pg_trigger where not tgisinternal
      and tgname in ('trg_marquer_scellement', 'trg_verifier_negociation_date')) = 2)::text
union all
select 'Aucun autre déclencheur ne notifie que ceux documentés',
  (not exists (
    select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
    where not t.tgisinternal and p.prosrc ilike '%notifier(%'
      and p.proname not in ('notifier_nouveau_pacte', 'notifier_reponse_pacte', 'notifier_nouveau_message',
                            'notifier_demande_remplacement', 'annuler_si_double_absence')))::text;
