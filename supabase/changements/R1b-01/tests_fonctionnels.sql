-- R1b-01 — tests fonctionnels après déploiement (exécutés par la porte).
-- Effets : une push « Test technique R1b » sur l'appareil de Kevin, et deux
-- appels directs refusés. Les réponses arrivent de façon asynchrone dans
-- net._http_response ; la session de travail les vérifie en lecture seule.
begin;

-- 1. Chemin légitime : notifier() vers le compte de Kevin → attendu HTTP 200.
select public.notifier(
  (select id from auth.users where email = 'kevinarner@hotmail.com' and email_confirmed_at is not null),
  'Test technique R1b',
  'Vérification des notifications après R1b. Rien à faire.',
  '{}'::jsonb);

-- 2. Appels directs avec la clé anon (publique, celle de l'app) : sans jeton,
--    puis avec un jeton inventé → attendu HTTP 403 pour les deux.
--    profile_id fictif : même en cas d'échec du correctif, aucune push.
select
  net.http_post(
    url := 'https://ssciqjpaibdorvnkkhsk.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNzY2lxanBhaWJkb3J2bmtraHNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0MjUyOTEsImV4cCI6MjEwMzAwMTI5MX0.9LjNBwizEopgqMvPbScG8YetBFkVrnYk_zKII4BXJ98'),
    body := jsonb_build_object('profile_id', '00000000-0000-4000-8000-000000000000',
                               'title', 'R1b test anon', 'body', 'R1b test anon')
  ) as requete_anon_sans_jeton,
  net.http_post(
    url := 'https://ssciqjpaibdorvnkkhsk.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNzY2lxanBhaWJkb3J2bmtraHNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0MjUyOTEsImV4cCI6MjEwMzAwMTI5MX0.9LjNBwizEopgqMvPbScG8YetBFkVrnYk_zKII4BXJ98',
      'x-swend-jeton', gen_random_uuid()::text),
    body := jsonb_build_object('profile_id', '00000000-0000-4000-8000-000000000000',
                               'title', 'R1b test anon', 'body', 'R1b test anon')
  ) as requete_anon_jeton_invente;

commit;
