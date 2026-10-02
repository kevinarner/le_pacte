-- R1b-01 — jeton à usage unique, lié au contenu, entre public.notifier() et
-- send-notification ; notifier() n'envoie plus la clé service_role.
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
     or exists (select 1 from pg_proc where proname = 'consommer_jeton_notification') then
    raise exception 'R1b-01 : objets R1b déjà présents';
  end if;
end $$;

-- 2. Jetons à usage unique (aucun accès pour l'app, ni direct pour service_role).
--    Jamais le jeton brut : son empreinte SHA-256, et celle du corps exact de
--    la notification qu'il autorise (profil, titre, texte, données).
create table public.notification_jetons (
  empreinte        bytea primary key check (octet_length(empreinte) = 32),
  charge_empreinte bytea not null check (octet_length(charge_empreinte) = 32),
  cree_le          timestamptz not null default now()
);
alter table public.notification_jetons owner to postgres;
alter table public.notification_jetons enable row level security;
revoke all on table public.notification_jetons from public, anon, authenticated, service_role;

-- 3. Consommation par send-notification (clé service_role), sur le corps BRUT
--    reçu : vrai une seule fois, si le jeton a été émis il y a moins de
--    15 minutes POUR CE CORPS. Empreintes calculées sur les mêmes formes
--    canoniques que notifier() (uuid::text ; jsonb::text). Un corps différent
--    ou illisible ne consomme rien. Le delete sur la clé primaire est
--    atomique : deux consommations concurrentes, une seule réussit.
create function public.consommer_jeton_notification(p_jeton uuid, p_charge text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_charge bytea;
begin
  begin
    v_charge := sha256(convert_to(p_charge::jsonb::text, 'UTF8'));
  exception when others then
    return false;  -- corps illisible : refus, sans message contenant le corps
  end;
  delete from public.notification_jetons
  where empreinte = sha256(convert_to(p_jeton::text, 'UTF8'))
    and charge_empreinte = v_charge
    and cree_le > now() - interval '15 minutes';
  return found;
end;
$$;
alter function public.consommer_jeton_notification(uuid, text) owner to postgres;
revoke execute on function public.consommer_jeton_notification(uuid, text) from public, anon, authenticated;
grant execute on function public.consommer_jeton_notification(uuid, text) to service_role;

-- 4. notifier() : la clé anon publique suffit à la passerelle ; l'autorisation
--    réelle est le jeton lié au corps. La clé service_role (secret Vault) n'est
--    plus lue ni envoyée. create or replace conserve ses droits (R1).
create or replace function public.notifier(p_profile_id uuid, p_title text, p_body text, p_data jsonb default '{}'::jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_charge jsonb;
  v_jeton uuid;
begin
  begin
    v_charge := jsonb_build_object(
      'profile_id', p_profile_id,
      'title', p_title,
      'body', p_body,
      'data', p_data
    );

    -- R1b : jeton à usage unique, lié à ce corps. Le jeton brut part dans
    -- l'en-tête ; seules les empreintes du jeton et du corps sont stockées.
    delete from public.notification_jetons where cree_le < now() - interval '1 day';
    v_jeton := gen_random_uuid();
    insert into public.notification_jetons (empreinte, charge_empreinte)
    values (sha256(convert_to(v_jeton::text, 'UTF8')),
            sha256(convert_to(v_charge::text, 'UTF8')));

    perform net.http_post(
      url := 'https://ssciqjpaibdorvnkkhsk.supabase.co/functions/v1/send-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNzY2lxanBhaWJkb3J2bmtraHNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0MjUyOTEsImV4cCI6MjEwMzAwMTI5MX0.9LjNBwizEopgqMvPbScG8YetBFkVrnYk_zKII4BXJ98',
        'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNzY2lxanBhaWJkb3J2bmtraHNrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0MjUyOTEsImV4cCI6MjEwMzAwMTI5MX0.9LjNBwizEopgqMvPbScG8YetBFkVrnYk_zKII4BXJ98',
        'x-swend-jeton', v_jeton::text
      ),
      body := v_charge
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
     <> 'cfb0159e1a33d7f77bd390baaf66a2f3' then
    raise exception 'R1b-01 : corps de notifier() inattendu après remplacement';
  end if;
  if (select position('vault' in prosrc) from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure) <> 0 then
    raise exception 'R1b-01 : notifier() lit encore un secret Vault';
  end if;
  if (select proacl::text from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'R1b-01 : droits de notifier() modifiés';
  end if;
  if has_function_privilege('anon', 'public.consommer_jeton_notification(uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'public.consommer_jeton_notification(uuid,text)', 'execute')
     or not has_function_privilege('service_role', 'public.consommer_jeton_notification(uuid,text)', 'execute') then
    raise exception 'R1b-01 : droits de consommer_jeton_notification() incorrects';
  end if;
  if has_table_privilege('anon', 'public.notification_jetons', 'select,insert,update,delete,truncate')
     or has_table_privilege('authenticated', 'public.notification_jetons', 'select,insert,update,delete,truncate')
     or not (select relrowsecurity from pg_class where oid = 'public.notification_jetons'::regclass) then
    raise exception 'R1b-01 : notification_jetons accessible à l''app ou sans RLS';
  end if;
  if (select string_agg(attname || ':' || format_type(atttypid, atttypmod), ',' order by attnum)
      from pg_attribute where attrelid = 'public.notification_jetons'::regclass and attnum > 0 and not attisdropped)
     <> 'empreinte:bytea,charge_empreinte:bytea,cree_le:timestamp with time zone' then
    raise exception 'R1b-01 : notification_jetons doit contenir seulement des empreintes et cree_le (jamais le jeton brut)';
  end if;
  if (select pg_get_userbyid(relowner) from pg_class where oid = 'public.notification_jetons'::regclass) <> 'postgres'
     or (select pg_get_userbyid(proowner) from pg_proc where oid = 'public.consommer_jeton_notification(uuid,text)'::regprocedure) <> 'postgres'
     or (select pg_get_userbyid(proowner) from pg_proc where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure) <> 'postgres' then
    raise exception 'R1b-01 : propriétaire inattendu (postgres attendu)';
  end if;
end $$;

commit;
