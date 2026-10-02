-- R2-01 — rollback : fonctions d'origine à l'identique (définitions relues en
-- production le 03/10/2026), objets R2 supprimés, les 2 Swends remis dans
-- l'état sauvegardé. Une transaction. Refuse si l'un des 2 Swends a changé
-- depuis R2-01 (décision humaine). La sauvegarde est conservée. À combiner
-- avec le retour à l'app précédente (gh-pages), voir paquet.md.
begin;

do $$
begin
  if to_regclass('sauvegarde.r2_01_pactes_20261003') is null
     or (select count(*) from sauvegarde.r2_01_pactes_20261003) <> 2 then
    raise exception 'R2-01 rollback : sauvegarde absente';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_verrou_zz_dates_swend') then
    raise exception 'R2-01 rollback : R2-01 n''est pas appliqué';
  end if;
  if (select count(*) from public.pactes
      where (id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6' and dates_proposees = '["2026-11-17T18:00:00.000Z"]'::jsonb
             and date_retenue = '2026-11-17T18:00:00Z' and statut = 'confirme')
         or (id = '6cb94c32-f2d7-49e8-9fec-24cff795cccf' and dates_proposees = '["2026-12-01T19:00:00.000Z"]'::jsonb
             and date_retenue is null and statut = 'enAttenteChoixDateDestinataire')) <> 2 then
    raise exception 'R2-01 rollback : un des 2 Swends a changé depuis R2-01 (décision humaine, rien n''est modifié)';
  end if;
end $$;

-- 1. Fonctions d'origine (copie exacte de pg_get_functiondef en production).
CREATE OR REPLACE FUNCTION public.formater_date_heure_fr(p_date timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select
    (array['dimanche','lundi','mardi','mercredi','jeudi','vendredi','samedi'])[extract(dow from p_date)::int + 1]
    || ' ' || extract(day from p_date)::int
    || ' ' || (array['janvier','février','mars','avril','mai','juin','juillet',
                      'août','septembre','octobre','novembre','décembre'])[extract(month from p_date)::int]
    || ' à ' || to_char(p_date, 'HH24"h"MI');
$function$
;

CREATE OR REPLACE FUNCTION public.verifier_delai_minimum_swend()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
$function$
;

-- 2. Objets R2.
drop trigger if exists trg_verrou_zz_dates_swend on public.pactes;
drop function if exists public.verifier_dates_swend();
drop function if exists public.dates_proposees_canoniques(jsonb);
drop function if exists public.instants_proposes(jsonb);
drop function if exists public.instant_date_proposee(jsonb);

-- 3. Les 2 Swends dans l'état sauvegardé (même suspension ciblée du
--    déclencheur de négociation que dans appliquer.sql).
alter table public.pactes disable trigger trg_verifier_negociation_date;
update public.pactes p
set dates_proposees = s.dates_proposees, date_retenue = s.date_retenue
from sauvegarde.r2_01_pactes_20261003 s
where s.id = p.id;
alter table public.pactes enable trigger trg_verifier_negociation_date;

-- 4. Assertions.
do $$
begin
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.formater_date_heure_fr(timestamptz)'::regprocedure) <> '4ae6b1caae1331b77d00ad54b56e43a3'
     or (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
         where oid = 'public.verifier_delai_minimum_swend()'::regprocedure) <> '839c15e1fd904e035d7003e5d1240422' then
    raise exception 'R2-01 rollback : fonctions non rétablies à l''identique';
  end if;
  if exists (select 1 from pg_proc where proname in ('instant_date_proposee', 'instants_proposes', 'dates_proposees_canoniques', 'verifier_dates_swend'))
     or exists (select 1 from pg_trigger where tgname = 'trg_verrou_zz_dates_swend') then
    raise exception 'R2-01 rollback : objets R2 encore présents';
  end if;
  if exists (select 1 from public.pactes p join sauvegarde.r2_01_pactes_20261003 s using (id)
             where (p.statut, p.dates_proposees, p.date_retenue, p.nombre_echanges_date, p.scelle_le)
                   is distinct from (s.statut, s.dates_proposees, s.date_retenue, s.nombre_echanges_date, s.scelle_le)) then
    raise exception 'R2-01 rollback : Swends non rétablis';
  end if;
  if (select tgenabled from pg_trigger where tgname = 'trg_verifier_negociation_date' and tgrelid = 'public.pactes'::regclass) <> 'O'
     or (select tgenabled from pg_trigger where tgname = 'trg_verrou_delai_minimum_swend' and tgrelid = 'public.pactes'::regclass) <> 'D' then
    raise exception 'R2-01 rollback : état des déclencheurs inattendu';
  end if;
end $$;

commit;
