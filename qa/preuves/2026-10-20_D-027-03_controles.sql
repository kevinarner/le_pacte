-- D-027-03 — contrôles en LECTURE SEULE autour du déploiement (endpoint
-- …/database/query/read-only uniquement ; aucun job déclenché à la main).
-- Préparés le 20/10/2026 (Go de préparation d'Eliot) ; résultats de la
-- relecture du 20/10 à 14:51 UTC : 2026-10-20_D-027-03_preparation.txt.

-- =====================================================================
-- A. Juste avant le « Go D-027-03 » d'exécution : préconditions exactes
--    du paquet et état des Swends (attendu entre crochets).
-- =====================================================================
select json_build_object(
 'maintenant', now(),
 'd027_02_applique', to_regclass('public.fils_imprevu_fermes') is not null,                       -- [true]
 'd027_03_absent', not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('echeance_h3_atteinte', 'appliquer_echeances_h3')),                           -- [true]
 'empreintes_conformes', (select count(*) from (values
    ('ajouter_et_demander_remplacement', 'd1e31b1225cbc29dbde728653e46d426'),
    ('annuler_demande_remplacement', '0b313996d6679b5eb80a21347ef49978'),
    ('envoyer_demandes_remplacement', '2b2bb34414a655a6ffc3dd07ce3ca726'),
    ('envoyer_rappels_dus', 'fa9ffe2576c7950f8555660332b95ced'),
    ('figer_swends_passes', '2803314c7ef40523b367df0dab59a605'),
    ('je_peux_finalement_venir', '9631961e9c168952cbc9e0c25584463f'),
    ('repondre_demande_remplacement', '902fd1203365bfbe2e234d5152610b44'),
    ('se_desister_du_remplacement', 'ce38814eb3f7e8b883fcfe0cced2dd78')) a(nom, md5)
    join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
    where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5),                                 -- [8]
 'jobs', (select json_agg(json_build_object('nom', jobname, 'planif', schedule, 'actif', active,
     'role', username, 'base', database) order by jobname) from cron.job),
     -- [swend-chat-apres * * * * *, swend-gel-a-h */5, swend-rappels */5 ; actifs, postgres/postgres ; pas de swend-echeance-h3]
 'cron_schedule', to_regprocedure('cron.schedule(text, text, text)') is not null,                 -- [true]
 'imprevus_non_resolus_passes_ou_proches', (select count(*) from public.pactes p where p.statut = 'confirme'
    and p.date_retenue <= now() + interval '3 hours 10 minutes'
    and not exists (select 1 from public.swends_figes f where f.pacte_id = p.id)
    and exists (select 1 from public.imprevus_declares d where d.pacte_id = p.id
      and not exists (select 1 from public.remplacants r where r.pacte_id = p.id and r.cote = d.cote and r.selectionne))), -- [0]
 'scelles_heure_dans_3h', (select count(*) from public.pactes p where p.statut = 'confirme'
    and p.scelle_le is not null and p.date_retenue > now() and p.date_retenue <= now() + interval '3 hours'),          -- [0]
 'fenetre_h3_h', (select count(*) from public.pactes p where p.statut = 'confirme' and p.date_retenue > now()
    and now() >= p.date_retenue - interval '3 hours'),                                             -- [0]
 'sauvegarde_absente', to_regclass('sauvegarde.d027_03_fonctions_20261020') is null              -- [true]
) as r;

-- =====================================================================
-- B. Juste après l'exécution par la porte (verifier.sql a déjà tourné
--    dans la porte ; ceci le confirme hors de la transaction).
-- =====================================================================
select json_build_object(
 'fonctions_testees', (select count(*) from (values
    ('ajouter_et_demander_remplacement', '41d62d5c89670158a44a3eb57fb146d4'),
    ('annuler_demande_remplacement', 'd4f041ba4caafe35ad85b31b1742f8df'),
    ('appliquer_echeances_h3', '4c4e93a84e4b29187324c980896274d6'),
    ('echeance_h3_atteinte', '57ea12a3892a202ebec0b942113e0471'),
    ('envoyer_demandes_remplacement', '7bb8a3ad2d46036b260192354b3d6012'),
    ('envoyer_rappels_dus', 'e1ba350897cefd6b75f460fb87821481'),
    ('figer_swends_passes', '0e7b3cbd9e73679d5750f0eb8f2d21eb'),
    ('je_peux_finalement_venir', 'c1ae4f8bd5140f7eed108040376fc754'),
    ('repondre_demande_remplacement', '8f6e448b412d297ec245d74d53468ee7'),
    ('se_desister_du_remplacement', '5f64a11b94a473d7796f6240d14d89ca')) a(nom, md5)
    join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
    where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5),                                 -- [10]
 'echeance_exposee_app', has_function_privilege('authenticated', 'public.appliquer_echeances_h3(timestamptz)', 'execute')
    or has_function_privilege('anon', 'public.appliquer_echeances_h3(timestamptz)', 'execute'),  -- [false]
 'droits_modifies', (select count(*) from sauvegarde.d027_03_fonctions_20261020 s
    join pg_proc p on p.proname = s.nom and p.pronamespace = 'public'::regnamespace
    where (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a) is distinct from s.droits), -- [0]
 'jobs', (select json_agg(json_build_object('nom', jobname, 'planif', schedule, 'commande', command,
     'actif', active, 'role', username, 'base', database) order by jobname) from cron.job),
     -- [4 jobs : + swend-echeance-h3 * * * * * « select public.appliquer_echeances_h3() », actif, postgres/postgres]
 'annulations_echeance_h3', (select count(*) from public.pactes where annule_motif = 'echeance_h3'),   -- [0]
 'swends_changes', (select count(*) from public.pactes p join sauvegarde.d027_03_pactes_20261020 s on s.id = p.id
    where p.statut is distinct from s.statut or p.date_retenue is distinct from s.date_retenue),   -- [0]
 'sauvegarde', (select count(*) from sauvegarde.d027_03_fonctions_20261020) || ' fonctions / '
    || (select count(*) from sauvegarde.d027_03_pactes_20261020) || ' Swends'                     -- [8 fonctions / 2 Swends]
) as r;

-- =====================================================================
-- C. Au moins 6 minutes après la fin de l'exécution : les 4 jobs tournent.
--    Remplacer <fin> par l'heure de fin du reçu (UTC).
-- =====================================================================
select j.jobname, j.schedule, count(d.*) as executions,
       count(*) filter (where d.status = 'succeeded') as reussies,
       count(*) filter (where d.status = 'failed') as echecs,
       min(d.start_time) as premiere, max(d.start_time) as derniere,
       max(d.end_time - d.start_time) as duree_max,
       string_agg(distinct d.return_message, ' | ') filter (where d.status <> 'succeeded') as messages_echec
  from cron.job j left join cron.job_run_details d on d.jobid = j.jobid and d.start_time > '<fin>'
 group by j.jobname, j.schedule order by j.jobname;
-- [swend-echeance-h3 : environ une exécution par minute, toutes succeeded ;
--  swend-chat-apres : idem ; swend-gel-a-h et swend-rappels : une toutes les
--  5 minutes, succeeded (ils appellent maintenant l'échéance) ; 0 échec]
