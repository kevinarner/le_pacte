-- Reconstruction locale du schéma de production Swend AVANT les scripts de
-- supabase/migrations/ (tables, rôles, premières policies RLS, triggers).
-- Ce n'est PAS une copie de la production : elle reproduit ce que décrit
-- ARCHITECTURE.md (sections 4 et 5). Les migrations versionnées sont
-- ensuite appliquées par-dessus, telles qu'exécutées en production.
--
-- Différences volontaires :
--  * auth.uid() lit le JWT transmis par PostgREST (comme Supabase) ;
--  * notifier() écrit dans notifications_log au lieu d'appeler l'Edge
--    Function (aucun envoi réel) ;
--  * synchroniser_remplacants_caches() simplifiée (1 emplacement par côté).

-- 1. Schéma minimal (tables, RLS, fonctions historiques) --------------

create extension if not exists pgcrypto;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema public to anon, authenticated;

create schema auth;
grant usage on schema auth to anon, authenticated;
-- Comptes Supabase Auth (version minimale : identité, email, confirmation).
-- Lue seulement par des fonctions serveur (D-025) ; jamais par l'app.
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz);

create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table profiles (
  id uuid primary key,
  prenom text, nom text,
  telephone text
);
create unique index profiles_telephone_unique on profiles (telephone) where telephone <> '';

create table restaurants (id uuid primary key default gen_random_uuid(), nom text);

create table pactes (
  id uuid primary key default gen_random_uuid(),
  statut text not null,
  date_retenue timestamptz,
  restaurant_id uuid references restaurants(id),
  initiateur_id uuid, initiateur_nom text,
  destinataire_id uuid, destinataire_nom text, destinataire_telephone text,
  initiateur_remplacant_1_nom text, initiateur_remplacant_1_telephone text,
  destinataire_remplacant_1_nom text, destinataire_remplacant_1_telephone text
);

create table remplacants (
  id uuid primary key default gen_random_uuid(),
  pacte_id uuid not null references pactes(id),
  cote text not null check (cote in ('initiateur', 'destinataire')),
  prenom text, nom text, telephone text, email text,
  selectionne boolean not null default false,
  profil_id uuid references profiles(id)
);

create table messages (
  id uuid primary key default gen_random_uuid(),
  remplacant_id uuid not null references remplacants(id),
  expediteur_id uuid, contenu text,
  created_at timestamptz default now()
);

-- Droits par défaut façon Supabase : tout accordé, RLS filtre.
grant all on all tables in schema public to anon, authenticated;

alter table profiles enable row level security;
create policy profiles_moi on profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy pactes_insert on pactes for insert to authenticated
  with check (initiateur_id = auth.uid());
alter table pactes enable row level security;
alter table remplacants enable row level security;
alter table messages enable row level security;

create function est_remplacant_du_pacte(p_pacte_id uuid) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from remplacants where pacte_id = p_pacte_id and profil_id = auth.uid())
$$;

create policy pactes_select on pactes for select to authenticated
  using (initiateur_id = auth.uid() or destinataire_id = auth.uid()
         or est_remplacant_du_pacte(id));
create policy pactes_update on pactes for update to authenticated
  using (initiateur_id = auth.uid() or destinataire_id = auth.uid());

create policy remplacants_select on remplacants for select to authenticated
  using (
    profil_id = auth.uid()
    or exists (select 1 from pactes p where p.id = pacte_id and (
         (cote = 'initiateur' and p.initiateur_id = auth.uid())
      or (cote = 'destinataire' and p.destinataire_id = auth.uid()))));
create policy remplacants_insert on remplacants for insert to authenticated
  with check (exists (select 1 from pactes p where p.id = pacte_id and (
         (cote = 'initiateur' and p.initiateur_id = auth.uid())
      or (cote = 'destinataire' and p.destinataire_id = auth.uid()))));
-- Policy UPDATE du titulaire telle qu'elle existait (direct update de
-- selectionne / demande_statut depuis l'app) : la migration v2 doit
-- rendre ces écritures directes impossibles malgré elle.
create policy remplacants_update on remplacants for update to authenticated
  using (exists (select 1 from pactes p where p.id = pacte_id and (
         (cote = 'initiateur' and p.initiateur_id = auth.uid())
      or (cote = 'destinataire' and p.destinataire_id = auth.uid()))));

create policy messages_all on messages for all to authenticated using (true);

-- Journal des notifications (remplace l'appel HTTP réel).
create table notifications_log (
  id bigserial primary key, profile_id uuid, titre text, corps text, data jsonb,
  created_at timestamptz default clock_timestamp()
);
create function notifier(p_profile_id uuid, p_title text, p_body text, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into notifications_log (profile_id, titre, corps, data)
  values (p_profile_id, p_title, p_body, p_data);
end $$;

create function trouver_profil_par_telephone(p_telephone text) returns uuid
language sql security definer set search_path = public as $$
  select id from profiles where telephone = p_telephone limit 1
$$;
grant execute on function trouver_profil_par_telephone(text) to authenticated;

-- Reconstruit d'après la description validée : ignore tout sauf un
-- passage à selectionne = true, puis annule si l'autre côté a déjà un
-- remplaçant sélectionné.
create function annuler_si_double_absence() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.selectionne is not true then
    return new;
  end if;
  if exists (select 1 from remplacants
             where pacte_id = new.pacte_id and cote <> new.cote and selectionne = true) then
    update pactes set statut = 'annuleDoubleAbsence' where id = new.pacte_id;
  end if;
  return new;
end $$;
create trigger trg_annuler_si_double_absence
  after insert or update of selectionne on remplacants
  for each row execute function annuler_si_double_absence();

-- Version simplifiée du cache historique (1 slot par côté) : sert
-- seulement à vérifier que le trigger coexiste avec les nouveaux verrous.
create function synchroniser_remplacants_caches() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_pacte uuid := coalesce(new.pacte_id, old.pacte_id);
begin
  update pactes p set
    initiateur_remplacant_1_nom = (select nom from remplacants where pacte_id = v_pacte and cote = 'initiateur' order by id limit 1),
    destinataire_remplacant_1_nom = (select nom from remplacants where pacte_id = v_pacte and cote = 'destinataire' order by id limit 1)
  where p.id = v_pacte;
  return null;
end $$;
create trigger trg_synchroniser_remplacants_caches
  after insert or update or delete on remplacants
  for each row execute function synchroniser_remplacants_caches();


-- 2. Compléments nécessaires à l'app réelle (via PostgREST) -------------

create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid
$$;

alter table profiles add column if not exists email text;
alter table restaurants add column if not exists lien text,
  add column if not exists creneaux_dejeuner jsonb not null default '[]'::jsonb,
  add column if not exists creneaux_diner jsonb not null default '[]'::jsonb;

alter table pactes
  add column if not exists type text not null default 'diner',
  add column if not exists dates_proposees jsonb not null default '[]'::jsonb,
  add column if not exists nombre_echanges_date int not null default 0,
  add column if not exists created_at timestamptz not null default now();

create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id) on delete cascade,
  token text unique, plateforme text, created_at timestamptz default now()
);
alter table device_tokens enable row level security;
create policy device_tokens_moi on device_tokens for all to authenticated
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());
grant all on device_tokens to authenticated;

create policy restaurants_lecture on restaurants for select to authenticated using (true);
alter table restaurants enable row level security;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login password 'authenticator' noinherit;
  end if;
end $$;
grant anon, authenticated to authenticator;
grant usage on schema public, auth to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;

-- Messages : comme en production (titulaire du côté concerné ou personne
-- de confiance liée), via la RLS de remplacants — plus de "tout lisible".
drop policy if exists messages_all on messages;
create policy messages_select on messages for select to authenticated
  using (exists (select 1 from remplacants r where r.id = remplacant_id));
create policy messages_insert on messages for insert to authenticated
  with check (expediteur_id = auth.uid()
              and exists (select 1 from remplacants r where r.id = remplacant_id));

-- Téléphone du titulaire pour le bouton d'appel côté personne de confiance
-- (existe en production, décrite dans ARCHITECTURE.md).
create or replace function telephone_titulaire_du_pacte(p_remplacant_id uuid) returns text
language sql security definer set search_path = public as $$
  select case when r.cote = 'initiateur' then pi.telephone else pd.telephone end
  from remplacants r join pactes p on p.id = r.pacte_id
  left join profiles pi on pi.id = p.initiateur_id
  left join profiles pd on pd.id = p.destinataire_id
  where r.id = p_remplacant_id and r.profil_id = auth.uid()
$$;
grant execute on function telephone_titulaire_du_pacte(uuid) to authenticated;

-- 3. Privilèges colonne par colonne sur pactes, comme en production ----------
-- En production, l'app ne lit pactes que colonne par colonne (GRANT SELECT
-- (colonnes) ; ARCHITECTURE.md section 4) : les colonnes d'historique
-- (*_remplacant_N_*), puis celles ajoutées plus tard par les migrations
-- (destinataire_telephone_e164, scelle_le, annule_par, annule_le) ne sont
-- pas lisibles. La réplique reproduit ce SELECT par colonne pour que le banc
-- détecte toute lecture d'une colonne non accordée (y compris « select * »).
-- INSERT / UPDATE / DELETE restent accordés au niveau de la table (les
-- règles d'écriture sont portées par la RLS et les déclencheurs).
revoke select on pactes from anon, authenticated;
grant select (id, type, statut, dates_proposees, date_retenue, nombre_echanges_date,
              restaurant_id, initiateur_id, initiateur_nom, destinataire_id,
              destinataire_nom, destinataire_telephone, created_at)
  on pactes to authenticated;
