-- Migration : convention temporelle (R2) et date retenue parmi les dates
-- proposées (D-025b). À exécuter après delai_minimum_swend.sql. Sûre à
-- ré-exécuter. Ne modifie aucune donnée : la conversion des Swends existants
-- est faite par le change packet de production (R2-01), avec sauvegarde.
--
-- Convention : l'heure métier est l'heure murale d'Europe/Paris ; un
-- rendez-vous est stocké comme un instant absolu. `date_retenue` reste un
-- timestamptz. `dates_proposees` reste un jsonb, mais chaque élément est une
-- chaîne ISO 8601 AVEC fuseau explicite, enregistrée sous la forme canonique
-- UTC « 2026-11-17T18:00:00.000Z ». Une chaîne sans fuseau (ancien format, lu
-- en UTC par erreur : 19:00 à Paris devenait 20:00 en hiver) est refusée
-- (`date_sans_fuseau`) au lieu d'être interprétée silencieusement.
--
-- Contenu :
--  1. instant_date_proposee(jsonb) / instants_proposes(jsonb) : lecture
--     stricte des dates proposées.
--  2. formater_date_heure_fr(timestamptz) : texte des push « Une date a été
--     choisie » / « Pacte confirmé » à l'heure de Paris (formatait en UTC).
--  3. verifier_delai_minimum_swend() (D-025) : lisait dates_proposees avec
--     unnest(), qui n'existe pas pour un jsonb (toute création par un
--     utilisateur non fondateur échouait) ; son déclencheur, désactivé en
--     production à cause de ce bug, est réactivé (état cible : actif).
--  4. Déclencheur verifier_dates_swend(), pour TOUTE écriture (app, fonctions
--     serveur, SQL Editor) : forme canonique des dates proposées, et D-025b —
--     la date retenue doit être l'une des dates proposées (même instant),
--     refus `date_non_proposee`. Aucune exception : aucune fonction serveur
--     n'écrit ces colonnes (vérifié le 03/10) ; déplacer un Swend revient à
--     changer les deux colonnes ensemble. Une app périmée ne peut donc pas
--     réenregistrer une heure décalée. Nommé pour passer après tous les gardes
--     existants : leurs erreurs restent prioritaires.
--
-- Inchangés (déjà corrects sur des instants, conversion explicite en Paris) :
-- echeance_rappel, date_rappel_fr, heure_rappel_fr, texte_rappel,
-- ouverture_chat_apres_swend (règle de D-023b inchangée), date_minimale_swend,
-- figer_swends_passes, vue reservations_a_suivre, memoriser_swend_supprime.

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

-- Forme canonique enregistrée : UTC, suffixe Z, sans perte — millisecondes
-- (« 2026-11-17T18:00:00.000Z », ce que l'app envoie), microsecondes si
-- l'instant en a ; comme DateTime.toUtc().toIso8601String() en Dart.
create or replace function public.dates_proposees_canoniques(p_dates jsonb)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(
           to_char(i at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.')
           || case when extract(microseconds from i)::bigint % 1000 = 0
                   then to_char(i at time zone 'UTC', 'MS') else to_char(i at time zone 'UTC', 'US') end
           || 'Z') order by n), '[]'::jsonb)
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

-- État cible du déclencheur D-025 : actif. Il avait été désactivé en
-- production à cause du bug unnest(jsonb) corrigé ci-dessus (sans effet au
-- banc QA, où il est déjà actif).
alter table public.pactes enable trigger trg_verrou_delai_minimum_swend;

-- 4. Forme canonique et D-025b (toute écriture) -----------------------------------

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
  if new.date_retenue is not null
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

-- Vérification (résultat affiché) ------------------------------------------------
select 'R2 : 19:00 à Paris en hiver = 18:00 UTC, push « mardi 17 novembre à 19h00 »' as verification,
  public.formater_date_heure_fr('2026-11-17T18:00:00Z') = 'mardi 17 novembre à 19h00'
  and public.formater_date_heure_fr('2026-07-07T17:00:00Z') = 'mardi 7 juillet à 19h00'
  and public.dates_proposees_canoniques('["2026-11-17T19:00:00+01:00"]') = '["2026-11-17T18:00:00.000Z"]'::jsonb
  as ok
union all
select 'R2 : déclencheur des dates en place (après les gardes existants), déclencheur D-025 actif',
  exists (select 1 from pg_trigger where tgname = 'trg_verrou_zz_dates_swend'
            and tgrelid = 'public.pactes'::regclass and not tgisinternal)
  and (select tgenabled = 'O' from pg_trigger where tgname = 'trg_verrou_delai_minimum_swend'
         and tgrelid = 'public.pactes'::regclass);
