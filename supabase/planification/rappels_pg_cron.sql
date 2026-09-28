-- Planification des rappels automatiques (D-021) — ACTIVE EN PRODUCTION
-- depuis le 28/09 (après la migration 20260927040000_rappels_jour_j.sql). Ce fichier n'est pas une migration : le banc QA ne l'applique
-- pas (il appelle le moteur directement avec un instant contrôlé).
--
-- Effet : toutes les 5 minutes, la base exécute envoyer_rappels_dus(), qui
-- envoie les rappels J-7 / J-3 / J-1 / Jour J dus (fenêtre de 30 minutes
-- après chaque échéance, jamais en double).
--
-- 1. Activer l'extension pg_cron (une seule fois). Équivalent dans le
--    dashboard : Integrations → Cron → Enable (ou Database → Extensions →
--    pg_cron). Sans effet si elle est déjà activée.
create extension if not exists pg_cron;

-- 2. Programmer le moteur (remplace une programmation existante du même nom).
select cron.unschedule(jobid) from cron.job where jobname = 'swend-rappels';
select cron.schedule('swend-rappels', '*/5 * * * *', 'select public.envoyer_rappels_dus()');

-- 3. Vérification : une ligne, active, toutes les 5 minutes.
select jobname, schedule, command, active from cron.job where jobname = 'swend-rappels';

-- Plus tard, pour vérifier les exécutions :
--   select status, start_time, return_message from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'swend-rappels')
--   order by start_time desc limit 10;
-- Pour arrêter les rappels :
--   select cron.unschedule('swend-rappels');
