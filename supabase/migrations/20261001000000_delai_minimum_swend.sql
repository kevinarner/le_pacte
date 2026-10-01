-- Migration : délai minimum avant un Swend (D-025).
-- À exécuter après chat_apres_swend.sql. Sûre à ré-exécuter.
--
-- Règle : pour un Swend créé par un utilisateur standard, aucune date
-- proposée (création ou contre-proposition) ni la date retenue ne peut tomber
-- avant la date de création, en heure de Paris, + 15 jours. Exemple : créé le
-- 1er octobre → première date possible le 16 octobre (toute heure).
--
-- Contenu :
--  1. comptes_fondateurs : les comptes exemptés, par email (table interne,
--     jamais accessible à l'app).
--  2. pactes.date_minimale (date) : calculée par le serveur à la création, et
--     uniquement par lui (Europe/Paris) ; null pour un Swend créé par un
--     compte fondateur (exempté pour toute sa négociation) et pour les Swends
--     existants (pas de rétroactivité). Jamais modifiable par l'app.
--  3. date_minimale_nouveau_swend() : première date possible pour un Swend
--     que la personne connectée créerait maintenant (auth.uid(), aucun
--     paramètre) ; null si elle est fondatrice. Utilisée par l'app pour le
--     calendrier et par le déclencheur.
--  4. Déclencheur verifier_delai_minimum_swend() (appels de l'app seulement) :
--     pose date_minimale à la création, contrôle les dates proposées (création
--     et contre-propositions) et la date retenue ; refus `date_trop_proche`.
--
-- Ne change aucune autre règle (2 contre-propositions au plus, jours,
-- créneaux, statuts) ni aucune politique existante. Le SQL Editor, le service
-- role et les fonctions serveur ne sont pas concernés.

-- 1. Comptes fondateurs ---------------------------------------------------------
-- Reconnus par l'email CONFIRMÉ de leur compte Supabase Auth (auth.users),
-- jamais par profiles.email (modifiable par l'utilisateur) ni par une valeur
-- envoyée par l'app.

create table if not exists public.comptes_fondateurs (
  email text primary key check (email = lower(btrim(email))),
  ajoute_le timestamptz not null default now()
);
alter table public.comptes_fondateurs enable row level security;
revoke all on table public.comptes_fondateurs from public, anon, authenticated;
insert into public.comptes_fondateurs (email) values
  ('kevinarner@hotmail.com'),
  ('eliotschlang@gmail.com'),
  ('eliotschlang@icloud.com')
on conflict (email) do nothing;

-- 2. Date minimale d'un Swend ----------------------------------------------------

alter table public.pactes add column if not exists date_minimale date;
-- L'app lit les colonnes de pactes une à une (D-024) : celle-ci lui est
-- accordée en lecture seulement (le calendrier de la négociation).
grant select (date_minimale) on public.pactes to authenticated;

-- Création à cet instant → première date possible (jour de Paris + 15).
create or replace function public.date_minimale_swend(p_creation timestamptz)
returns date
language sql
immutable
set search_path = public
as $$
  select (p_creation at time zone 'Europe/Paris')::date + 15
$$;

-- 3. Première date possible pour la personne connectée -----------------------------
-- auth.uid() uniquement : impossible de tester l'exemption d'un autre compte.
-- SECURITY DEFINER pour lire auth.users et comptes_fondateurs, qui restent
-- inaccessibles à l'app ; ne renvoie qu'une date (ou null).

create or replace function public.date_minimale_nouveau_swend()
returns date
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (
      select 1 from auth.users u
      join public.comptes_fondateurs f on f.email = lower(btrim(u.email))
      where u.id = auth.uid() and u.email_confirmed_at is not null
    ) then null
    else public.date_minimale_swend(now())
  end
$$;
revoke execute on function public.date_minimale_nouveau_swend() from public, anon;
grant execute on function public.date_minimale_nouveau_swend() to authenticated;

-- 4. Contrôle des dates ---------------------------------------------------------------
-- SECURITY INVOKER : current_user distingue l'app (authenticated / anon) du
-- SQL Editor et des fonctions serveur. À la création, initiateur_id est
-- forcément auth.uid() (politique pactes_insert) : l'exemption suit le
-- créateur, pour toute la négociation.

create or replace function public.verifier_delai_minimum_swend()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.date_minimale := public.date_minimale_nouveau_swend();
  elsif new.date_minimale is distinct from old.date_minimale then
    raise exception 'modification_interdite';
  end if;

  if new.date_minimale is null then
    return new;
  end if;

  if (tg_op = 'INSERT' or new.dates_proposees is distinct from old.dates_proposees)
     and exists (select 1 from unnest(new.dates_proposees) d
                 where (d at time zone 'Europe/Paris')::date < new.date_minimale) then
    raise exception 'date_trop_proche' using detail = new.date_minimale::text;
  end if;

  if new.date_retenue is not null
     and (tg_op = 'INSERT' or new.date_retenue is distinct from old.date_retenue)
     and (new.date_retenue at time zone 'Europe/Paris')::date < new.date_minimale then
    raise exception 'date_trop_proche' using detail = new.date_minimale::text;
  end if;

  return new;
end;
$$;

-- Nom choisi pour passer après les gardes existants (ordre alphabétique) :
-- un numéro invalide, une date passée ou une négociation terminée gardent
-- leur erreur habituelle.
drop trigger if exists trg_verrou_delai_minimum_swend on public.pactes;
create trigger trg_verrou_delai_minimum_swend
  before insert or update on public.pactes
  for each row execute function public.verifier_delai_minimum_swend();

-- Vérification (résultat affiché) ------------------------------------------
select 'Comptes fondateurs : 3 adresses, table inaccessible à l''app' as verification,
  ((select count(*) from public.comptes_fondateurs
    where email in ('kevinarner@hotmail.com', 'eliotschlang@gmail.com', 'eliotschlang@icloud.com')) = 3
   and not has_table_privilege('authenticated', 'public.comptes_fondateurs', 'select')
   and not has_table_privilege('anon', 'public.comptes_fondateurs', 'select'))::text as resultat
union all
select 'Date minimale : lisible par l''app (jamais modifiable par elle : déclencheur)',
  (has_column_privilege('authenticated', 'public.pactes', 'date_minimale', 'select'))::text
union all
select 'Calcul en heure de Paris : créé le 1er oct. à 23:30 → 16 octobre',
  (public.date_minimale_swend('2026-10-01 23:30 Europe/Paris') = date '2026-10-16'
   and public.date_minimale_swend('2026-10-01 00:30 Europe/Paris') = date '2026-10-16')::text
union all
select 'Première date possible : fonction sans paramètre, réservée aux comptes connectés',
  (has_function_privilege('authenticated', 'public.date_minimale_nouveau_swend()', 'execute')
   and not has_function_privilege('anon', 'public.date_minimale_nouveau_swend()', 'execute')
   and (select prosecdef and pronargs = 0 from pg_proc
        where oid = 'public.date_minimale_nouveau_swend()'::regprocedure))::text
union all
select 'Déclencheur de contrôle des dates en place',
  exists (select 1 from pg_trigger where not tgisinternal
          and tgname = 'trg_verrou_delai_minimum_swend'
          and tgrelid = 'public.pactes'::regclass)::text;
