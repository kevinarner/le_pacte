-- R1b-01 — vérification après la partie SQL (lecture seule, endpoint
-- …/read-only). Lève une erreur si un point est faux : la porte s'arrête
-- alors AVANT le déploiement de l'Edge Function.
do $$
begin
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     <> 'cb331a844d5b2a5d155adeb6a948e558' then
    raise exception 'R1b-01 vérification : corps de notifier() inattendu';
  end if;
  if (select proacl::text from pg_proc
      where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure)
     is distinct from '{postgres=X/postgres}'
     or has_function_privilege('anon', 'public.notifier(uuid,text,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.notifier(uuid,text,text,jsonb)', 'execute') then
    raise exception 'R1b-01 vérification : droits de notifier() incorrects';
  end if;
  if not has_function_privilege('service_role', 'public.consommer_jeton_notification(uuid)', 'execute')
     or has_function_privilege('anon', 'public.consommer_jeton_notification(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.consommer_jeton_notification(uuid)', 'execute') then
    raise exception 'R1b-01 vérification : droits de consommer_jeton_notification() incorrects';
  end if;
  if has_table_privilege('anon', 'public.notification_jetons', 'select,insert,update,delete,truncate')
     or has_table_privilege('authenticated', 'public.notification_jetons', 'select,insert,update,delete,truncate') then
    raise exception 'R1b-01 vérification : notification_jetons accessible à l''app';
  end if;
  if (select string_agg(attname || ':' || format_type(atttypid, atttypmod), ',' order by attnum)
      from pg_attribute where attrelid = 'public.notification_jetons'::regclass and attnum > 0 and not attisdropped)
     <> 'empreinte:bytea,cree_le:timestamp with time zone' then
    raise exception 'R1b-01 vérification : notification_jetons contient autre chose que empreinte et cree_le';
  end if;
end $$;

select
  (select proacl::text from pg_proc where oid = 'public.notifier(uuid,text,text,jsonb)'::regprocedure) as notifier_acl,
  (select proacl::text from pg_proc where oid = 'public.consommer_jeton_notification(uuid)'::regprocedure) as consommer_acl,
  (select relrowsecurity from pg_class where oid = 'public.notification_jetons'::regclass) as jetons_rls,
  (select count(*) from public.notification_jetons) as jetons_en_attente;
