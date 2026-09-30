-- Planification du chat après le Swend (D-023b) — PAS ENCORE ACTIVÉE EN PRODUCTION.
-- À exécuter à la main dans le SQL Editor de Supabase, UNIQUEMENT après :
--   1. la migration 20260930010000_chat_apres_swend.sql ;
--   2. le déploiement de l'app qui sait afficher le chat après le Swend
--      (et de l'Edge Function send-notification avec le lien web du chat).
-- Ce fichier n'est pas une migration : le banc QA ne l'applique pas (il
-- appelle le moteur directement, avec un instant contrôlé).
--
-- Effet : chaque minute, la base exécute ouvrir_chats_apres_swend(). Pour
-- chaque Swend confirmé, scellé et figé (D-023a) dont l'heure d'ouverture est
-- atteinte (H+3 si c'est au plus tard 23:00 heure de Paris le jour du Swend,
-- sinon 10:00 le lendemain) : le chat s'ouvre entre les deux titulaires et le
-- remplaçant sélectionné s'il existe, et chacun reçoit « Alors, ce Swend ? /
-- Le silence est levé. Vous pouvez maintenant en reparler dans le chat. »
-- (seulement si le retard ne dépasse pas 12 heures). Jamais deux fois.
--
-- Pas de rattrapage : seuls les Swends dont l'heure d'ouverture est
-- postérieure à la mise en service (posée par la migration, table
-- chat_apres_swend_service) reçoivent un chat. Pour reporter la borne au
-- moment de l'activation, exécuter AVANT l'étape 2 :
--   update public.chat_apres_swend_service set mise_en_service = now();

-- 1. Extension pg_cron : déjà activée (jobs swend-rappels, swend-gel-a-h).
create extension if not exists pg_cron;

-- 2. Programmer le moteur (remplace une programmation existante du même nom).
select cron.unschedule(jobid) from cron.job where jobname = 'swend-chat-apres';
select cron.schedule('swend-chat-apres', '* * * * *', 'select public.ouvrir_chats_apres_swend()');

-- 3. Vérification : une ligne, active, chaque minute.
select jobname, schedule, command, active from cron.job where jobname = 'swend-chat-apres';

-- Plus tard, pour vérifier les exécutions (status = succeeded, 1 row) :
--   select status, start_time, return_message from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'swend-chat-apres')
--   order by start_time desc limit 10;
-- Chats ouverts : select * from public.chats_apres_swend order by ouvert_le desc limit 20;
-- Anomalies (chat non ouvert) : select * from public.anomalies_chat_apres_swend;
-- Pour arrêter : select cron.unschedule('swend-chat-apres');
