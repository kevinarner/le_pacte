-- D-027-03 — sauvegarde ciblée, avant toute modification. Une transaction.
-- Copie, dans le schéma interne `sauvegarde` (aucun accès pour l'app), la
-- définition exacte, les droits et l'empreinte des 7 fonctions remplacées,
-- et l'état d'annulation de tous les Swends (identifiants, statuts et dates
-- seulement). Échoue (rien n'est créé) si l'état n'est pas celui relu le
-- 20/10/2026, si D-027-03 est déjà appliqué ou si la sauvegarde existe déjà.
begin;

do $$
begin
  -- Ordre des migrations : D-027-02 appliqué (annulation unique, motif
  -- echeance_h3 admis), D-027-03 pas encore.
  if to_regclass('public.fils_imprevu_fermes') is null
     or not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'appliquer_annulation')
     or pg_get_constraintdef((select oid from pg_constraint where conname = 'pactes_annule_motif_valeurs'
                              and conrelid = 'public.pactes'::regclass)) not ilike '%echeance_h3%' then
    raise exception 'D-027-03 : D-027-02 pas encore appliqué (ordre des migrations)';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
             and proname in ('echeance_h3_atteinte', 'appliquer_echeances_h3')) then
    raise exception 'D-027-03 : déjà appliqué (en tout ou partie)';
  end if;
  -- Les 7 fonctions remplacées sont exactement celles relues en production
  -- le 20/10/2026 (corps normalisé), une seule par nom.
  if (select count(*) from (values
    ('ajouter_et_demander_remplacement', 'd1e31b1225cbc29dbde728653e46d426'),
    ('annuler_demande_remplacement', '0b313996d6679b5eb80a21347ef49978'),
    ('envoyer_demandes_remplacement', '2b2bb34414a655a6ffc3dd07ce3ca726'),
    ('envoyer_rappels_dus', 'fa9ffe2576c7950f8555660332b95ced'),
    ('je_peux_finalement_venir', '9631961e9c168952cbc9e0c25584463f'),
    ('repondre_demande_remplacement', '902fd1203365bfbe2e234d5152610b44'),
    ('se_desister_du_remplacement', 'ce38814eb3f7e8b883fcfe0cced2dd78')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 7
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('ajouter_et_demander_remplacement', 'annuler_demande_remplacement', 'envoyer_demandes_remplacement', 'envoyer_rappels_dus', 'je_peux_finalement_venir', 'repondre_demande_remplacement', 'se_desister_du_remplacement')) <> 7 then
    raise exception 'D-027-03 : les fonctions à remplacer diffèrent de celles relues (paquet à refaire)';
  end if;
  -- Le moteur des rappels (qui appliquera aussi l'échéance) : job actif,
  -- toutes les 5 minutes, inchangé. Le job de l'échéance n'existe pas encore.
  if (select count(*) from cron.job where jobname = 'swend-rappels' and active
      and schedule = '*/5 * * * *' and command = 'select public.envoyer_rappels_dus()') <> 1 then
    raise exception 'D-027-03 : job swend-rappels différent de celui relu (paquet à refaire)';
  end if;
  if exists (select 1 from cron.job where jobname = 'swend-echeance-h3')
     or to_regprocedure('cron.schedule(text, text, text)') is null then
    raise exception 'D-027-03 : job swend-echeance-h3 déjà présent, ou pg_cron indisponible';
  end if;
  -- Aucun Swend en imprévu dont l'heure tombe dans les 3 h 10 qui viennent :
  -- sinon le premier passage du job l'annulerait aussitôt (arbitrage nécessaire).
  if exists (select 1 from public.pactes p
             where p.statut = 'confirme' and p.date_retenue > now()
               and p.date_retenue <= now() + interval '3 hours 10 minutes'
               and exists (select 1 from public.imprevus_declares d where d.pacte_id = p.id)) then
    raise exception 'D-027-03 : un Swend en imprévu a son heure dans moins de 3 h 10 (arbitrage nécessaire)';
  end if;
  if to_regclass('sauvegarde.d027_03_fonctions_20261020') is not null
     or to_regclass('sauvegarde.d027_03_pactes_20261020') is not null then
    raise exception 'D-027-03 sauvegarde : déjà faite';
  end if;
end $$;

create schema if not exists sauvegarde;
revoke all on schema sauvegarde from public, anon, authenticated;

create table sauvegarde.d027_03_fonctions_20261020 as
select p.proname as nom, pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_functiondef(p.oid) as definition,
       (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a) as droits,
       md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) as md5_corps, now() as sauvegarde_le
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in ('ajouter_et_demander_remplacement', 'annuler_demande_remplacement', 'envoyer_demandes_remplacement', 'envoyer_rappels_dus', 'je_peux_finalement_venir', 'repondre_demande_remplacement', 'se_desister_du_remplacement');

create table sauvegarde.d027_03_pactes_20261020 as
select p.id, p.statut, p.date_retenue, p.annule_par, p.annule_le, p.annule_motif, now() as sauvegarde_le
from public.pactes p;

revoke all on table sauvegarde.d027_03_fonctions_20261020 from public, anon, authenticated;
revoke all on table sauvegarde.d027_03_pactes_20261020 from public, anon, authenticated;

do $$
begin
  if (select count(*) from sauvegarde.d027_03_fonctions_20261020) <> 7
     or (select count(*) from sauvegarde.d027_03_pactes_20261020) <> (select count(*) from public.pactes) then
    raise exception 'D-027-03 sauvegarde : copie incomplète';
  end if;
  if has_schema_privilege('authenticated', 'sauvegarde', 'usage') or has_schema_privilege('anon', 'sauvegarde', 'usage') then
    raise exception 'D-027-03 sauvegarde : le schéma sauvegarde est accessible à l''app';
  end if;
end $$;

commit;
