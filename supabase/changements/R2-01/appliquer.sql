-- R2-01 — convention temporelle (R2) et D-025b, puis conversion des 2 Swends
-- existants. Une seule transaction : préconditions, migration
-- supabase/migrations/20261003000000_fuseaux_horaires.sql (sections 1 à 4,
-- copie exacte), conversion des données, assertions. Toute assertion fausse
-- annule tout. Prérequis : sauvegarde.sql exécuté (même porte, étape
-- précédente).
begin;

-- 0. Préconditions --------------------------------------------------------------
do $$
begin
  -- Sauvegarde faite, et les 2 Swends toujours dans l'état sauvegardé.
  if to_regclass('sauvegarde.r2_01_pactes_20261003') is null
     or to_regclass('sauvegarde.r2_01_fonctions_20261003') is null
     or (select count(*) from sauvegarde.r2_01_pactes_20261003) <> 2 then
    raise exception 'R2-01 : sauvegarde absente ou incomplète';
  end if;
  if exists (select 1 from sauvegarde.r2_01_pactes_20261003 s join public.pactes p using (id)
             where (p.statut, p.dates_proposees, p.date_retenue, p.nombre_echanges_date)
                   is distinct from (s.statut, s.dates_proposees, s.date_retenue, s.nombre_echanges_date))
     or (select count(*) from public.pactes where id in ('8c6c9d64-d13d-44c6-8d0a-dec7eae430d6', '6cb94c32-f2d7-49e8-9fec-24cff795cccf')) <> 2 then
    raise exception 'R2-01 : un des 2 Swends a changé depuis la sauvegarde (paquet à refaire)';
  end if;
  -- Tout autre Swend (créé par la nouvelle app) a déjà des dates avec fuseau.
  if exists (select 1 from public.pactes p, jsonb_array_elements(p.dates_proposees) e
             where p.id not in ('8c6c9d64-d13d-44c6-8d0a-dec7eae430d6', '6cb94c32-f2d7-49e8-9fec-24cff795cccf')
               and (jsonb_typeof(e) <> 'string'
                    or (e #>> '{}') !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)$')) then
    raise exception 'R2-01 : un autre Swend a une date sans fuseau (ancienne app) : paquet à refaire';
  end if;
  -- Fonctions et déclencheurs dans l'état relu le 03/10.
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.formater_date_heure_fr(timestamptz)'::regprocedure) <> '4ae6b1caae1331b77d00ad54b56e43a3'
     or (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
         where oid = 'public.verifier_delai_minimum_swend()'::regprocedure) <> '839c15e1fd904e035d7003e5d1240422' then
    raise exception 'R2-01 : fonctions différentes de celles relues le 03/10';
  end if;
  if exists (select 1 from pg_proc where proname in ('instant_date_proposee', 'instants_proposes', 'dates_proposees_canoniques', 'verifier_dates_swend'))
     or exists (select 1 from pg_trigger where tgname = 'trg_verrou_zz_dates_swend') then
    raise exception 'R2-01 : objets R2 déjà présents';
  end if;
  if (select tgenabled from pg_trigger where tgname = 'trg_verifier_negociation_date' and tgrelid = 'public.pactes'::regclass) <> 'O'
     or (select tgenabled from pg_trigger where tgname = 'trg_verrou_delai_minimum_swend' and tgrelid = 'public.pactes'::regclass) <> 'D' then
    raise exception 'R2-01 : état des déclencheurs différent de celui relu le 03/10';
  end if;
end $$;

-- ================================================================================
-- Migration 20261003000000_fuseaux_horaires.sql (sections 1 à 4, copie exacte)
-- ================================================================================

-- 1. Lecture stricte des dates proposées -----------------------------------------

create or replace function public.instant_date_proposee(p_valeur jsonb)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
begin
  if jsonb_typeof(p_valeur) is distinct from 'string'
     or (p_valeur #>> '{}') !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}(:?\d{2})?)$' then
    raise exception 'date_sans_fuseau'
      using detail = left(coalesce(p_valeur::text, 'null'), 64);
  end if;
  return (p_valeur #>> '{}')::timestamptz;
end;
$$;

-- Instants d'un tableau de dates proposées (ordre conservé).
create or replace function public.instants_proposes(p_dates jsonb)
returns timestamptz[]
language plpgsql
stable
set search_path = public
as $$
begin
  if jsonb_typeof(p_dates) is distinct from 'array' then
    raise exception 'date_sans_fuseau' using detail = 'dates_proposees doit être un tableau';
  end if;
  return coalesce(
    (select array_agg(public.instant_date_proposee(e) order by n)
     from jsonb_array_elements(p_dates) with ordinality as t(e, n)),
    '{}');
end;
$$;

-- Forme canonique enregistrée : UTC, millisecondes, suffixe Z (celle que
-- l'app envoie : DateTime.toUtc().toIso8601String()).
create or replace function public.dates_proposees_canoniques(p_dates jsonb)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(to_char(i at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) order by n), '[]'::jsonb)
  from unnest(public.instants_proposes(p_dates)) with ordinality as t(i, n);
$$;

-- 2. Texte des push de négociation à l'heure de Paris ------------------------------
-- « mardi 17 novembre à 19h00 ». Utilisée par notifier_reponse_pacte().

create or replace function public.formater_date_heure_fr(p_date timestamptz)
returns text
language sql
stable
as $$
  select
    (array['dimanche','lundi','mardi','mercredi','jeudi','vendredi','samedi'])[extract(dow from p_date at time zone 'Europe/Paris')::int + 1]
    || ' ' || extract(day from p_date at time zone 'Europe/Paris')::int
    || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet',
                      'août','septembre','octobre','novembre','décembre'])[extract(month from p_date at time zone 'Europe/Paris')::int]
    || ' à ' || to_char(p_date at time zone 'Europe/Paris', 'HH24"h"MI');
$$;

-- 3. D-025 : lecture jsonb des dates proposées ------------------------------------

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
     and exists (select 1 from unnest(public.instants_proposes(new.dates_proposees)) d
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

-- 4. Forme canonique (tous les rôles) et D-025b (app) ------------------------------

create or replace function public.verifier_dates_swend()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or new.dates_proposees is distinct from old.dates_proposees then
    new.dates_proposees := public.dates_proposees_canoniques(new.dates_proposees);
  end if;

  -- D-025b : la date retenue est l'une des dates proposées (même instant).
  if current_user in ('authenticated', 'anon')
     and new.date_retenue is not null
     and (tg_op = 'INSERT'
          or new.date_retenue is distinct from old.date_retenue
          or new.dates_proposees is distinct from old.dates_proposees)
     and not (new.date_retenue = any (public.instants_proposes(new.dates_proposees))) then
    raise exception 'date_non_proposee';
  end if;

  return new;
end;
$$;

-- « zz » : après tous les déclencheurs BEFORE existants (ordre alphabétique).
drop trigger if exists trg_verrou_zz_dates_swend on public.pactes;
create trigger trg_verrou_zz_dates_swend
  before insert or update of dates_proposees, date_retenue on public.pactes
  for each row execute function public.verifier_dates_swend();

-- ================================================================================
-- Fin de la copie de la migration
-- ================================================================================

-- 5. Conversion des 2 Swends existants -------------------------------------------
-- Chaînes sans fuseau = heure murale de Paris choisie dans l'app. La date
-- retenue avait été lue en UTC : 19:00 choisi → 19:00 UTC (20:00 à Paris) ;
-- elle redevient 19:00 à Paris = 18:00 UTC. Le déclencheur de négociation
-- (dates modifiables seulement pendant la négociation, compteur + 1) est
-- suspendu le temps de ces 2 mises à jour, dans cette transaction ; le
-- nouveau déclencheur des dates les contrôle (forme canonique).
alter table public.pactes disable trigger trg_verifier_negociation_date;
update public.pactes
set dates_proposees = '["2026-11-17T18:00:00.000Z"]', date_retenue = '2026-11-17T18:00:00Z'
where id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6';
update public.pactes
set dates_proposees = '["2026-12-01T19:00:00.000Z"]'
where id = '6cb94c32-f2d7-49e8-9fec-24cff795cccf';
alter table public.pactes enable trigger trg_verifier_negociation_date;

-- 6. Assertions avant validation de la transaction --------------------------------
do $$
begin
  -- Données converties, et rien d'autre de ces Swends n'a changé.
  if (select count(*) from public.pactes p join sauvegarde.r2_01_pactes_20261003 s using (id)
      where (p.id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6'
             and p.dates_proposees = '["2026-11-17T18:00:00.000Z"]'::jsonb and p.date_retenue = '2026-11-17T18:00:00Z'
             and to_char(p.date_retenue at time zone 'Europe/Paris', 'YYYY-MM-DD HH24:MI') = '2026-11-17 19:00')
         or (p.id = '6cb94c32-f2d7-49e8-9fec-24cff795cccf'
             and p.dates_proposees = '["2026-12-01T19:00:00.000Z"]'::jsonb and p.date_retenue is null
             and to_char((public.instants_proposes(p.dates_proposees))[1] at time zone 'Europe/Paris', 'YYYY-MM-DD HH24:MI') = '2026-12-01 20:00')) <> 2
     or exists (select 1 from public.pactes p join sauvegarde.r2_01_pactes_20261003 s using (id)
                where (p.statut, p.nombre_echanges_date, p.scelle_le) is distinct from (s.statut, s.nombre_echanges_date, s.scelle_le)) then
    raise exception 'R2-01 : conversion des 2 Swends inattendue';
  end if;
  -- Tous les Swends : dates canoniques, date retenue parmi les dates proposées.
  if exists (select 1 from public.pactes p
             where p.dates_proposees is distinct from public.dates_proposees_canoniques(p.dates_proposees)
                or (p.date_retenue is not null and not (p.date_retenue = any (public.instants_proposes(p.dates_proposees))))) then
    raise exception 'R2-01 : un Swend n''est pas conforme (forme canonique ou D-025b)';
  end if;
  -- Fonctions : corps attendus (identiques au banc QA), propriétaire postgres.
  if (select string_agg(p.proname || '=' || md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')), ',' order by p.proname)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('formater_date_heure_fr', 'verifier_delai_minimum_swend', 'instant_date_proposee',
                                                     'instants_proposes', 'dates_proposees_canoniques', 'verifier_dates_swend'))
     <> 'dates_proposees_canoniques=74bd927bd042b082699f4d9a72bc85d8,formater_date_heure_fr=c38b9d67f08572b22fa96c33153bbf42,'
        'instant_date_proposee=8302057a73139ee506783f0887a1621b,instants_proposes=fa81b5417d7dbb2d0589c8fcdb96ec0d,'
        'verifier_dates_swend=2453821d31ee487e399693f9ff161710,verifier_delai_minimum_swend=9df0eb6611672569e597b2d011060380' then
    raise exception 'R2-01 : corps de fonction inattendu';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname in ('formater_date_heure_fr', 'verifier_delai_minimum_swend', 'instant_date_proposee',
                   'instants_proposes', 'dates_proposees_canoniques', 'verifier_dates_swend')
               and (pg_get_userbyid(p.proowner) <> 'postgres' or p.prosecdef)) then
    raise exception 'R2-01 : propriétaire ou SECURITY DEFINER inattendu';
  end if;
  -- Texte des push à l'heure de Paris.
  if public.formater_date_heure_fr('2026-11-17T18:00:00Z') <> 'mardi 17 novembre à 19h00' then
    raise exception 'R2-01 : formater_date_heure_fr ne formate pas à l''heure de Paris';
  end if;
  -- Déclencheurs : nouveau actif, négociation réactivé, D-025 inchangé.
  if (select tgenabled from pg_trigger where tgname = 'trg_verrou_zz_dates_swend' and tgrelid = 'public.pactes'::regclass) is distinct from 'O'
     or (select tgenabled from pg_trigger where tgname = 'trg_verifier_negociation_date' and tgrelid = 'public.pactes'::regclass) <> 'O'
     or (select tgenabled from pg_trigger where tgname = 'trg_verrou_delai_minimum_swend' and tgrelid = 'public.pactes'::regclass) <> 'D' then
    raise exception 'R2-01 : état des déclencheurs inattendu';
  end if;
end $$;

commit;
