-- Contrôle D-023a (gel à H) — LECTURE SEULE, ne modifie rien.
-- À exécuter dans le SQL Editor juste après 20260929000000_gel_a_h.sql :
-- chaque ligne doit être à true. Avant la migration (ou après une
-- exécution partielle), certaines lignes sont à false.
select 'swends_figes : table présente, RLS activée, aucun accès pour l''app' as controle,
  (to_regclass('public.swends_figes') is not null
   and (select relrowsecurity from pg_class where oid = to_regclass('public.swends_figes'))
   and not has_table_privilege('authenticated', 'public.swends_figes', 'select')
   and not has_table_privilege('anon', 'public.swends_figes', 'select'))::text as resultat
union all
select 'figer_swends_passes(timestamptz) : présente, SECURITY DEFINER, non exécutable par l''app',
  (to_regprocedure('public.figer_swends_passes(timestamptz)') is not null
   and (select prosecdef from pg_proc where oid = to_regprocedure('public.figer_swends_passes(timestamptz)'))
   and not has_function_privilege('authenticated', 'public.figer_swends_passes(timestamptz)', 'execute')
   and not has_function_privilege('anon', 'public.figer_swends_passes(timestamptz)', 'execute'))::text
union all
select 'telephone_titulaire_accessible(uuid) : présente, exécutable par authenticated, pas par anon',
  (to_regprocedure('public.telephone_titulaire_accessible(uuid)') is not null
   and has_function_privilege('authenticated', 'public.telephone_titulaire_accessible(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.telephone_titulaire_accessible(uuid)', 'execute'))::text
union all
select 'Politiques RLS D-023a : les 7 politiques restrictives présentes, anciennes absentes',
  ((select count(*) from pg_policies where schemaname = 'public' and permissive = 'RESTRICTIVE'
      and policyname in ('pactes_acces_personne_de_confiance', 'remplacants_acces_personne_de_confiance',
                         'evenements_fil_lecture_autorisee', 'messages_lecture_apres_scellage',
                         'messages_ecriture_ouverte', 'messages_modification_ouverte',
                         'messages_suppression_ouverte')) = 7
   and not exists (select 1 from pg_policies where schemaname = 'public'
                   and policyname in ('messages_apres_scellage', 'remplacants_tiers_non_retire')))::text
union all
select 'Rattrapage : tous les Swends scellés déjà passés sont marqués traités',
  -- Requête dynamique (query_to_xml) : pas d'erreur si la table n'existe pas encore.
  (to_regclass('public.swends_figes') is not null
   and (xpath('/row/n/text()', query_to_xml(
          'select count(*) as n from public.pactes p
           where p.scelle_le is not null and p.date_retenue <= now()
             and not exists (select 1 from public.swends_figes f where f.pacte_id = p.id)',
          false, true, '')))[1]::text = '0')::text
union all
select 'Ancienne telephone_titulaire_du_pacte() : non exécutable par authenticated, anon ni public',
  (to_regprocedure('public.telephone_titulaire_du_pacte(uuid)') is null
   or (not has_function_privilege('authenticated', 'public.telephone_titulaire_du_pacte(uuid)', 'execute')
       and not has_function_privilege('anon', 'public.telephone_titulaire_du_pacte(uuid)', 'execute')
       and not exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                       where p.oid = to_regprocedure('public.telephone_titulaire_du_pacte(uuid)')
                         and a.grantee = 0 and a.privilege_type = 'EXECUTE')))::text
union all
select 'est_remplacant_du_pacte() : non redéfinie par D-023a (pas de retire_le dans son corps)',
  (to_regprocedure('public.est_remplacant_du_pacte(uuid)') is null
   or (select prosrc not like '%retire_le%' from pg_proc
       where oid = to_regprocedure('public.est_remplacant_du_pacte(uuid)')))::text;
