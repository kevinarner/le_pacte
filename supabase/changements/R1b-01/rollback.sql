-- R1b-01 — rollback SQL. À exécuter APRÈS le redéploiement de la version
-- précédente de send-notification (étape précédente du rollback) : l'ancienne
-- fonction ignore l'en-tête x-swend-jeton. Rétablit notifier() à l'identique
-- de la définition relue en production le 02/10 (droits conservés : R1), puis
-- supprime les objets R1b.
begin;

CREATE OR REPLACE FUNCTION public.notifier(p_profile_id uuid, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_service_role_key text;
begin
  begin
    select decrypted_secret into v_service_role_key
    from vault.decrypted_secrets
    where name = 'service_role_key_notifications'
    limit 1;

    if v_service_role_key is null then
      raise warning 'notifier(): secret Vault "service_role_key_notifications" introuvable, notification ignorée.';
      return;
    end if;

    perform net.http_post(
      url := 'https://ssciqjpaibdorvnkkhsk.supabase.co/functions/v1/send-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key
      ),
      body := jsonb_build_object(
        'profile_id', p_profile_id,
        'title', p_title,
        'body', p_body,
        'data', p_data
      )
    );
  exception when others then
    raise warning 'notifier(): échec de l''envoi ("%") : %', p_title, sqlerrm;
  end;
end;
$function$

;

drop function if exists public.consommer_jeton_notification(uuid);
drop table if exists public.notification_jetons;

do $$
begin
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     <> 'b377eb8917710850ebdf01541448879b' then
    raise exception 'R1b-01 rollback : notifier() ne correspond pas à la version d''origine';
  end if;
  if (select proacl::text from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'R1b-01 rollback : droits de notifier() modifiés (R1 doit rester)';
  end if;
end $$;

commit;
