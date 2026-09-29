-- Planification du gel à H (D-023a) — PAS ENCORE ACTIVÉE EN PRODUCTION.
-- À exécuter à la main dans le SQL Editor de Supabase, UNIQUEMENT après :
--   1. la migration 20260929000000_gel_a_h.sql (fonction figer_swends_passes) ;
--   2. le déploiement de l'app qui sait afficher l'événement « Le Swend a
--      commencé » (sinon une ancienne version afficherait une ligne vide).
-- Ce fichier n'est pas une migration : le banc QA ne l'applique pas (il
-- appelle le moteur directement, avec un instant contrôlé si besoin).
--
-- Effet : toutes les 5 minutes, la base exécute figer_swends_passes(). Pour
-- chaque Swend scellé dont l'heure est atteinte et pas encore traité : les
-- demandes encore en attente sont clôturées (push « La demande n’est plus
-- d’actualité / L’heure du Swend est passée. » aux personnes sollicitées, au
-- plus 12 heures après l'heure du Swend) et « Le Swend a commencé. Cette
-- conversation est désormais terminée. » est ajouté aux conversations ayant
-- eu une activité. Jamais deux fois (table swends_figes).
--
-- Les actions elles-mêmes (demander, accepter, se désister…) sont refusées par
-- la base dès l'heure du Swend, que ce job soit actif ou non : il ne fait que
-- les conséquences (clôture, push, événement), avec au plus 5 minutes d'écart.

-- 1. Extension pg_cron : déjà activée (job swend-rappels). Sans effet sinon.
create extension if not exists pg_cron;

-- 2. Programmer le moteur (remplace une programmation existante du même nom).
select cron.unschedule(jobid) from cron.job where jobname = 'swend-gel-a-h';
select cron.schedule('swend-gel-a-h', '*/5 * * * *', 'select public.figer_swends_passes()');

-- 3. Vérification : une ligne, active, toutes les 5 minutes.
select jobname, schedule, command, active from cron.job where jobname = 'swend-gel-a-h';

-- Plus tard, pour vérifier les exécutions (status = succeeded, 1 row) :
--   select status, start_time, return_message from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'swend-gel-a-h')
--   order by start_time desc limit 10;
-- Swends traités (rattrapage = true : déjà passés à la migration, rien envoyé) :
--   select * from public.swends_figes order by fige_le desc limit 20;
-- Pour arrêter le traitement automatique :
--   select cron.unschedule('swend-gel-a-h');
