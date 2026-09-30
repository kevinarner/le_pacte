-- Planification du chat après le Swend (D-023b) — PAS ENCORE ACTIVÉE EN PRODUCTION.
-- À exécuter à la main dans le SQL Editor de Supabase (tout le fichier, sans
-- rien sélectionner), UNIQUEMENT après :
--   1. la migration 20260930010000_chat_apres_swend.sql ;
--   2. le déploiement de l'Edge Function send-notification (lien web du chat)
--      et de l'app qui sait afficher le chat après le Swend.
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
-- PAS DE RATTRAPAGE : la mise en service réelle est l'activation de ce job.
-- Ce fichier repositionne la borne à now() ET crée le job dans la même
-- exécution (une seule transaction : now() est le même instant pour les deux,
-- et si une étape échoue, rien n'est appliqué). Aucun Swend dont l'heure
-- d'ouverture est antérieure à cette activation ne reçoit de chat.

-- 1. Extension pg_cron : déjà activée (jobs swend-rappels, swend-gel-a-h).
create extension if not exists pg_cron;

-- 2. Borne de mise en service = maintenant (créée si elle manquait).
insert into public.chat_apres_swend_service (id, mise_en_service)
values (true, now())
on conflict (id) do update set mise_en_service = excluded.mise_en_service;

-- 3. Programmer le moteur (remplace une programmation existante du même nom).
select cron.unschedule(jobid) from cron.job where jobname = 'swend-chat-apres';
select cron.schedule('swend-chat-apres', '* * * * *', 'select public.ouvrir_chats_apres_swend()');

-- 4. Vérification : borne posée à cet instant, job actif chaque minute.
select j.jobname, j.schedule, j.command, j.active,
       s.mise_en_service,
       (s.mise_en_service = now()) as borne_posee_a_l_activation
from cron.job j cross join public.chat_apres_swend_service s
where j.jobname = 'swend-chat-apres';

-- Plus tard, pour vérifier les exécutions (status = succeeded, 1 row) :
--   select status, start_time, return_message from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'swend-chat-apres')
--   order by start_time desc limit 10;
-- Chats ouverts : select * from public.chats_apres_swend order by ouvert_le desc limit 20;
-- Anomalies (chat non ouvert) : select * from public.anomalies_chat_apres_swend;
-- Pour arrêter : select cron.unschedule('swend-chat-apres');
