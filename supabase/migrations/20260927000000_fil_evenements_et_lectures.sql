-- Fil de discussion titulaire ↔ personne de confiance : événements
-- persistants ("Tu as demandé à Kevin de prendre ta place"...) et suivi
-- lu / non lu par conversation. À exécuter après destinataire_a_un_compte.sql.
-- Sûre à ré-exécuter. Ne modifie aucune donnée existante.
--
-- Confidentialité : un événement n'est lisible que par qui peut déjà lire
-- la fiche concernée (titulaire de ce côté, ou la personne de confiance
-- elle-même) — jamais par l'autre participant du Swend.

-- 1. Événements du fil ------------------------------------------------------
-- Une ligne par changement d'état d'une demande "Un imprévu ?". Écrite
-- uniquement par le déclencheur ci-dessous (aucune écriture depuis l'app).
-- Le texte est rédigé par l'app selon qui regarde (titulaire / tiers).

create table if not exists public.evenements_fil (
  id uuid primary key default gen_random_uuid(),
  remplacant_id uuid not null references public.remplacants(id) on delete cascade,
  code text not null check (code in (
    'demande_envoyee',   -- null → envoyee
    'demande_annulee',   -- envoyee → null (annulée par le titulaire)
    'demande_refusee',   -- envoyee → refusee
    'demande_acceptee',  -- envoyee → acceptee
    'desistement',       -- acceptee → desistee
    'demande_cloturee'   -- envoyee → cloturee (quelqu'un d'autre a accepté)
  )),
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists evenements_fil_par_fil
  on public.evenements_fil (remplacant_id, created_at);

alter table public.evenements_fil enable row level security;
revoke all on public.evenements_fil from public, anon, authenticated;
grant select on public.evenements_fil to authenticated;
drop policy if exists evenements_fil_lecture on public.evenements_fil;
create policy evenements_fil_lecture on public.evenements_fil
  for select to authenticated
  using (exists (select 1 from public.remplacants r where r.id = remplacant_id));

create or replace function public.journaliser_demande_remplacement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if new.demande_statut is not distinct from old.demande_statut then
    return new;
  end if;
  v_code := case
    when old.demande_statut is null and new.demande_statut = 'envoyee' then 'demande_envoyee'
    when old.demande_statut = 'envoyee' and new.demande_statut is null then 'demande_annulee'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'refusee' then 'demande_refusee'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'acceptee' then 'demande_acceptee'
    when old.demande_statut = 'acceptee' and new.demande_statut = 'desistee' then 'desistement'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'cloturee' then 'demande_cloturee'
  end;
  if v_code is not null then
    insert into evenements_fil (remplacant_id, code) values (new.id, v_code);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_journaliser_demande_remplacement on public.remplacants;
create trigger trg_journaliser_demande_remplacement
  after update of demande_statut on public.remplacants
  for each row execute function public.journaliser_demande_remplacement();

-- 2. Lu / non lu par conversation -----------------------------------------
-- Une ligne par (conversation, personne) : jusqu'à quand elle a lu. Un
-- message de l'autre personne plus récent = conversation non lue.

create table if not exists public.lectures_fil (
  remplacant_id uuid not null references public.remplacants(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  lu_le timestamptz not null default clock_timestamp(),
  primary key (remplacant_id, profile_id)
);

alter table public.lectures_fil enable row level security;
revoke all on public.lectures_fil from public, anon, authenticated;
grant select on public.lectures_fil to authenticated;
drop policy if exists lectures_fil_moi on public.lectures_fil;
create policy lectures_fil_moi on public.lectures_fil
  for select to authenticated
  using (profile_id = auth.uid());

-- Marque une conversation comme lue par la personne connectée, si elle y
-- participe (titulaire de ce côté, ou la personne de confiance elle-même).
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
      and (r.profil_id = v_uid
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

revoke execute on function public.marquer_fil_lu(uuid) from public, anon;
grant execute on function public.marquer_fil_lu(uuid) to authenticated;

-- Vérification (résultat affiché) ------------------------------------------
select 'Événements du fil : table + lecture protégée' as verification,
  (to_regclass('public.evenements_fil') is not null
   and has_table_privilege('authenticated', 'public.evenements_fil', 'select')
   and not has_table_privilege('authenticated', 'public.evenements_fil', 'insert'))::text as resultat
union all
select 'Déclencheur de journalisation en place',
  exists (select 1 from pg_trigger where tgname = 'trg_journaliser_demande_remplacement' and not tgisinternal)::text
union all
select 'Lectures : table + écriture seulement via marquer_fil_lu',
  (to_regclass('public.lectures_fil') is not null
   and not has_table_privilege('authenticated', 'public.lectures_fil', 'insert')
   and has_function_privilege('authenticated', 'public.marquer_fil_lu(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.marquer_fil_lu(uuid)', 'execute'))::text;
