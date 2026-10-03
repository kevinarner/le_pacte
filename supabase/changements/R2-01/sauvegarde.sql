-- R2-01 — sauvegarde ciblée, avant toute modification. Une transaction.
-- Copie, dans le schéma interne `sauvegarde` (aucun accès pour l'app) :
--  - les colonnes modifiées des 2 Swends (dates, date_minimale) et ce qui
--    permet de vérifier qu'ils n'ont pas bougé ;
--  - les définitions exactes des 2 fonctions remplacées, et l'état du
--    déclencheur D-025.
-- Échoue (rien n'est créé) si l'état n'est pas exactement celui relu le
-- 03/10/2026, ou si la sauvegarde existe déjà.
begin;

do $$
begin
  if (select count(*) from public.pactes
      where (id = '8c6c9d64-d13d-44c6-8d0a-dec7eae430d6' and statut = 'confirme'
             and dates_proposees = '["2026-11-17T19:00:00.000"]'::jsonb
             and date_retenue = '2026-11-17 19:00:00+00' and nombre_echanges_date = 0 and scelle_le is not null
             and date_minimale is null)
         or (id = '6cb94c32-f2d7-49e8-9fec-24cff795cccf' and statut = 'enAttenteChoixDateDestinataire'
             and dates_proposees = '["2026-12-01T20:00:00.000"]'::jsonb
             and date_retenue is null and nombre_echanges_date = 0 and scelle_le is null
             and date_minimale is null)) <> 2 then
    raise exception 'R2-01 sauvegarde : les 2 Swends ne sont plus dans l''état relu le 03/10 (paquet à refaire)';
  end if;
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.formater_date_heure_fr(timestamptz)'::regprocedure) <> '4ae6b1caae1331b77d00ad54b56e43a3'
     or (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
         where oid = 'public.verifier_delai_minimum_swend()'::regprocedure) <> '839c15e1fd904e035d7003e5d1240422' then
    raise exception 'R2-01 sauvegarde : fonctions différentes de celles relues le 03/10';
  end if;
  if (select tgenabled from pg_trigger where tgname = 'trg_verrou_delai_minimum_swend'
      and tgrelid = 'public.pactes'::regclass) <> 'D' then
    raise exception 'R2-01 sauvegarde : déclencheur D-025 dans un état différent de celui relu le 03/10 (désactivé)';
  end if;
  if has_schema_privilege('authenticated', 'sauvegarde', 'usage') or has_schema_privilege('anon', 'sauvegarde', 'usage') then
    raise exception 'R2-01 sauvegarde : le schéma sauvegarde est accessible à l''app';
  end if;
end $$;

create table sauvegarde.r2_01_pactes_20261003 as
select id, statut, dates_proposees, date_retenue, date_minimale, nombre_echanges_date, scelle_le, created_at,
       clock_timestamp() as sauvegarde_le
from public.pactes
where id in ('8c6c9d64-d13d-44c6-8d0a-dec7eae430d6', '6cb94c32-f2d7-49e8-9fec-24cff795cccf');

create table sauvegarde.r2_01_fonctions_20261003 as
select p.oid::regprocedure::text as fonction, pg_get_functiondef(p.oid) as definition,
       md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) as empreinte, clock_timestamp() as sauvegarde_le
from pg_proc p
where p.oid in ('public.formater_date_heure_fr(timestamptz)'::regprocedure,
                'public.verifier_delai_minimum_swend()'::regprocedure)
union all
select 'déclencheur trg_verrou_delai_minimum_swend', 'tgenabled = ' || t.tgenabled::text, null, clock_timestamp()
from pg_trigger t
where t.tgname = 'trg_verrou_delai_minimum_swend' and t.tgrelid = 'public.pactes'::regclass;

do $$
begin
  if (select count(*) from sauvegarde.r2_01_pactes_20261003) <> 2
     or (select count(*) from sauvegarde.r2_01_fonctions_20261003) <> 3 then
    raise exception 'R2-01 sauvegarde : sauvegarde incomplète';
  end if;
  if has_table_privilege('authenticated', 'sauvegarde.r2_01_pactes_20261003', 'select')
     or has_table_privilege('anon', 'sauvegarde.r2_01_pactes_20261003', 'select') then
    raise exception 'R2-01 sauvegarde : sauvegarde lisible par l''app';
  end if;
end $$;

commit;
