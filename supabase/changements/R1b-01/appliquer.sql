-- R1b-01 — jeton à usage unique entre public.notifier() et send-notification.
-- Une seule transaction : préconditions, changement, assertions. Toute
-- assertion fausse annule tout (la porte s'arrête avant le déploiement).
begin;

-- 1. Préconditions : production dans l'état relu le 02/10 (aucun écart).
do $$
begin
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     <> 'b377eb8917710850ebdf01541448879b' then
    raise exception 'R1b-01 : public.notifier() a changé depuis la préparation du paquet';
  end if;
  if (select proacl::text from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'R1b-01 : droits de public.notifier() inattendus (R1 attendu)';
  end if;
  if to_regclass('public.notification_jetons') is not null
     or to_regprocedure('public.consommer_jeton_notification(uuid)') is not null then
    raise exception 'R1b-01 : objets R1b déjà présents';
  end if;
end $$;

-- 2. Jetons à usage unique (aucun accès pour l'app, ni direct pour service_role).
create table public.notification_jetons (
  jeton   uuid primary key default gen_random_uuid(),
  cree_le timestamptz not null default now()
);
alter table public.notification_jetons owner to postgres;
alter table public.notification_jetons enable row level security;
revoke all on table public.notification_jetons from public, anon, authenticated, service_role;

-- 3. Consommation par send-notification (clé service_role) : vrai une seule
--    fois, pour un jeton émis il y a moins de 15 minutes.
create function public.consommer_jeton_notification(p_jeton uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  with consomme as (
    delete from public.notification_jetons
    where jeton = p_jeton and cree_le > now() - interval '15 minutes'
    returning 1
  )
  select exists (select 1 from consomme)
$$;
alter function public.consommer_jeton_notification(uuid) owner to postgres;
revoke execute on function public.consommer_jeton_notification(uuid) from public, anon, authenticated;
grant execute on function public.consommer_jeton_notification(uuid) to service_role;

-- 4. notifier() : même corps qu'avant, plus le jeton (en-tête x-swend-jeton).
--    create or replace conserve ses droits (R1 : postgres seulement).
create or replace function public.notifier(p_profile_id uuid, p_title text, p_body text, p_data jsonb default '{}'::jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_service_role_key text;
  v_jeton uuid;
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

    -- R1b : jeton à usage unique, consommé par send-notification.
    delete from public.notification_jetons where cree_le < now() - interval '1 day';
    insert into public.notification_jetons default values returning jeton into v_jeton;

    perform net.http_post(
      url := 'https://ssciqjpaibdorvnkkhsk.supabase.co/functions/v1/send-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key,
        'x-swend-jeton', v_jeton::text
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
$function$;

-- 5. Assertions avant validation de la transaction.
do $$
begin
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     <> '174a0a458ccc3dbec8ddbfb844691902' then
    raise exception 'R1b-01 : corps de notifier() inattendu après remplacement';
  end if;
  if (select proacl::text from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'R1b-01 : droits de notifier() modifiés';
  end if;
  if has_function_privilege('anon', 'public.consommer_jeton_notification(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.consommer_jeton_notification(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.consommer_jeton_notification(uuid)', 'execute') then
    raise exception 'R1b-01 : droits de consommer_jeton_notification() incorrects';
  end if;
  if has_table_privilege('anon', 'public.notification_jetons', 'select,insert,update,delete,truncate')
     or has_table_privilege('authenticated', 'public.notification_jetons', 'select,insert,update,delete,truncate')
     or not (select relrowsecurity from pg_class where oid = 'public.notification_jetons'::regclass) then
    raise exception 'R1b-01 : notification_jetons accessible à l''app ou sans RLS';
  end if;
  if (select pg_get_userbyid(relowner) from pg_class where oid = 'public.notification_jetons'::regclass) <> 'postgres'
     or (select pg_get_userbyid(proowner) from pg_proc where oid = 'public.consommer_jeton_notification(uuid)'::regprocedure) <> 'postgres'
     or (select pg_get_userbyid(proowner) from pg_proc where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure) <> 'postgres' then
    raise exception 'R1b-01 : propriétaire inattendu (postgres attendu)';
  end if;
end $$;

commit;
