-- Migration : suivi interne des réservations manuelles V1 (D-020).
-- À exécuter après scellage_et_negociation.sql. Sûre à ré-exécuter.
--
-- Outil STRICTEMENT INTERNE, utilisé par l'équipe depuis le dashboard /
-- SQL Editor de Supabase (rôle postgres) : l'application (anon,
-- authenticated) n'a aucun accès, ni en lecture ni en écriture. Aucun état
-- de réservation n'est visible des utilisateurs.
--
-- Données : crée une ligne de suivi `a_reserver` pour chaque Swend déjà
-- scellé (rattrapage, voir 4). Aucune autre donnée modifiée.
--
-- Le statut du Swend et le statut de la réservation restent deux
-- informations distinctes : annuler un Swend ne change JAMAIS
-- automatiquement le statut de réservation (une table réservée doit
-- éventuellement être annulée auprès du restaurant par l'équipe).

-- 1. Table de suivi --------------------------------------------------------

create table if not exists public.reservations_suivi (
  id uuid primary key default gen_random_uuid(),
  -- Une ligne par Swend. `set null` : si un participant supprime le Swend
  -- depuis l'app, la ligne de suivi est conservée (voir 3).
  pacte_id uuid unique references public.pactes(id) on delete set null,
  statut_reservation text not null default 'a_reserver'
    check (statut_reservation in ('a_reserver', 'reservee', 'probleme', 'annulee')),
  pris_en_charge_par text,
  nom_reservation text,
  reference_reservation text,
  note text,
  -- Renseignés seulement si le Swend est supprimé depuis l'app : la ligne
  -- garde alors de quoi retrouver la réservation.
  swend_supprime_le timestamptz,
  resume_swend_supprime text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Aucun accès pour l'application : ni droits, ni politique RLS.
alter table public.reservations_suivi enable row level security;
revoke all on table public.reservations_suivi from public, anon, authenticated;

create or replace function public.maj_reservations_suivi_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_reservations_suivi_updated_at on public.reservations_suivi;
create trigger trg_reservations_suivi_updated_at
  before update on public.reservations_suivi
  for each row execute function public.maj_reservations_suivi_updated_at();

-- 2. Création automatique au scellage --------------------------------------
-- scelle_le est posée par le déclencheur BEFORE marquer_scellement() (et non
-- par l'app) : on réagit donc à la transition null → non-null elle-même,
-- dans la même transaction que le scellage (atomique). `on conflict do
-- nothing` : idempotent, jamais de doublon.

create or replace function public.creer_suivi_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into reservations_suivi (pacte_id) values (new.id)
  on conflict (pacte_id) do nothing;
  return new;
end;
$$;
revoke execute on function public.creer_suivi_reservation() from public, anon, authenticated;

drop trigger if exists trg_creer_suivi_reservation_insert on public.pactes;
create trigger trg_creer_suivi_reservation_insert
  after insert on public.pactes
  for each row when (new.scelle_le is not null)
  execute function public.creer_suivi_reservation();

drop trigger if exists trg_creer_suivi_reservation_update on public.pactes;
create trigger trg_creer_suivi_reservation_update
  after update on public.pactes
  for each row when (old.scelle_le is null and new.scelle_le is not null)
  execute function public.creer_suivi_reservation();

-- 3. Swend supprimé depuis l'app -------------------------------------------
-- supprimer_pacte() permet à un participant de supprimer un Swend, même
-- scellé. Avant la suppression, on note sur la ligne de suivi quand et quoi
-- (participants, restaurant, date, heure) ; la clé étrangère passe ensuite à
-- null. Rien n'est supprimé ni modifié côté statut de réservation.

create or replace function public.memoriser_swend_supprime()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update reservations_suivi s
  set swend_supprime_le = now(),
      resume_swend_supprime = format('%s / %s — %s — %s à %s (Swend %s, statut %s)',
        coalesce(old.initiateur_nom, '?'), coalesce(old.destinataire_nom, '?'),
        coalesce((select r.nom from restaurants r where r.id = old.restaurant_id), '?'),
        coalesce(to_char(old.date_retenue at time zone 'Europe/Paris', 'DD/MM/YYYY'), '?'),
        coalesce(to_char(old.date_retenue at time zone 'Europe/Paris', 'HH24:MI'), '?'),
        old.id, old.statut)
  where s.pacte_id = old.id;
  return old;
end;
$$;
revoke execute on function public.memoriser_swend_supprime() from public, anon, authenticated;

drop trigger if exists trg_memoriser_swend_supprime on public.pactes;
create trigger trg_memoriser_swend_supprime
  before delete on public.pactes
  for each row execute function public.memoriser_swend_supprime();

-- 4. Rattrapage des Swends déjà scellés -------------------------------------
-- Crée uniquement les lignes manquantes (a_reserver) ; ne modifie aucune
-- ligne existante. Les Swends déjà passés ou annulés reçoivent aussi leur
-- ligne (un Swend scellé = une ligne) ; la vue n'y affiche aucune action.

create or replace function public.rattraper_reservations_suivi()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  insert into reservations_suivi (pacte_id)
  select p.id from pactes p where p.scelle_le is not null
  on conflict (pacte_id) do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.rattraper_reservations_suivi() from public, anon, authenticated;

select public.rattraper_reservations_suivi();

-- 5. Vue interne -----------------------------------------------------------
-- Une ligne par suivi, ce qui demande une action humaine en premier
-- (colonne a_faire), puis par date du rendez-vous. Dates et heures en heure
-- de Paris. security_invoker : même si un droit était accordé par erreur,
-- la vue ne contournerait pas la RLS de reservations_suivi.

create or replace view public.reservations_a_suivre
with (security_invoker = true) as
select
  case
    when s.statut_reservation = 'reservee'
         and (p.id is null or p.statut in ('annule', 'annuleDoubleAbsence'))
         and (p.date_retenue is null or p.date_retenue >= now())
      then 'Annuler la réservation au restaurant'
    when p.statut = 'confirme' and p.date_retenue >= now()
         and s.statut_reservation = 'a_reserver'
      then 'Réserver'
    when p.statut = 'confirme' and p.date_retenue >= now()
         and s.statut_reservation = 'probleme'
      then 'Problème : contacter les participants'
    else ''
  end as a_faire,
  p.id as swend_id,
  coalesce(p.statut, 'supprimé') as statut_swend,
  p.scelle_le,
  p.initiateur_nom as initiateur,
  pi.telephone as initiateur_telephone,
  p.destinataire_nom as destinataire,
  p.destinataire_telephone,
  r.nom as restaurant,
  p.type as repas,
  (p.date_retenue at time zone 'Europe/Paris')::date as date_rdv,
  to_char(p.date_retenue at time zone 'Europe/Paris', 'HH24:MI') as heure_rdv,
  s.statut_reservation,
  s.pris_en_charge_par,
  s.nom_reservation,
  s.reference_reservation,
  s.note,
  s.updated_at as derniere_modification,
  s.swend_supprime_le,
  s.resume_swend_supprime,
  s.id as suivi_id
from public.reservations_suivi s
left join public.pactes p on p.id = s.pacte_id
left join public.profiles pi on pi.id = p.initiateur_id
left join public.restaurants r on r.id = p.restaurant_id
order by
  (case
    when s.statut_reservation = 'reservee'
         and (p.id is null or p.statut in ('annule', 'annuleDoubleAbsence'))
         and (p.date_retenue is null or p.date_retenue >= now()) then 0
    when p.statut = 'confirme' and p.date_retenue >= now()
         and s.statut_reservation in ('a_reserver', 'probleme') then 0
    else 1
  end),
  p.date_retenue nulls last;

revoke all on table public.reservations_a_suivre from public, anon, authenticated;

-- Vérification (résultat affiché) ------------------------------------------
select 'Table et vue présentes' as verification,
  (to_regclass('public.reservations_suivi') is not null
   and to_regclass('public.reservations_a_suivre') is not null)::text as resultat
union all
select 'Chaque Swend scellé a exactement une ligne de suivi',
  (not exists (select 1 from public.pactes p where p.scelle_le is not null
     and (select count(*) from public.reservations_suivi s where s.pacte_id = p.id) <> 1))::text
union all
select 'Aucun accès pour l''app (anon, authenticated) à la table et à la vue',
  (not has_table_privilege('anon', 'public.reservations_suivi', 'select, insert, update, delete')
   and not has_table_privilege('authenticated', 'public.reservations_suivi', 'select, insert, update, delete')
   and not has_table_privilege('anon', 'public.reservations_a_suivre', 'select, insert, update, delete')
   and not has_table_privilege('authenticated', 'public.reservations_a_suivre', 'select, insert, update, delete'))::text
union all
select 'RLS activée sur la table de suivi',
  (select relrowsecurity from pg_class where oid = 'public.reservations_suivi'::regclass)::text
union all
select 'Déclencheurs en place (création au scellage, suppression, mise à jour)',
  ((select count(*) from pg_trigger where not tgisinternal and tgname in (
     'trg_creer_suivi_reservation_insert', 'trg_creer_suivi_reservation_update',
     'trg_memoriser_swend_supprime', 'trg_reservations_suivi_updated_at')) = 4)::text;
