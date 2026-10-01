-- Délai minimum avant un Swend (D-025). Utilise les outils de 10_imprevu.sql
-- (verifier). Dates relatives au jour de Paris d'aujourd'hui.
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set F '00000000-0000-0000-0000-000000000251'
\set N '00000000-0000-0000-0000-000000000252'
\set P '00000000-0000-0000-0000-000000000253'

-- Comptes : Eliot et David (standard), F fondateur (email confirmé), N
-- fondateur non confirmé, P « usurpateur » (profiles.email d'un fondateur).
insert into profiles (id, prenom, nom, telephone) values
 ('00000000-0000-0000-0000-00000000000e', 'Eliot', 'E', '0600000001'),
 ('00000000-0000-0000-0000-00000000000d', 'David', 'D', '0600000002'),
 ('00000000-0000-0000-0000-000000000251', 'Kevin', 'Fondateur', '0611000021'),
 ('00000000-0000-0000-0000-000000000252', 'Eliot', 'NonConfirme', '0611000022'),
 ('00000000-0000-0000-0000-000000000253', 'Paul', 'Usurpateur', '0611000023')
on conflict do nothing;
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-00000000000e', 'eliot@swend.test', now()),
 ('00000000-0000-0000-0000-00000000000d', 'david@swend.test', now()),
 ('00000000-0000-0000-0000-000000000251', 'KevinArner@Hotmail.com', now()),
 ('00000000-0000-0000-0000-000000000252', 'eliotschlang@icloud.com', null),
 ('00000000-0000-0000-0000-000000000253', 'paul@swend.test', now())
on conflict (id) do update set email = excluded.email, email_confirmed_at = excluded.email_confirmed_at;

-- ---------- outils ----------
-- Instant « jour de Paris d'aujourd'hui + n, à l'heure h » (Europe/Paris).
create or replace function dm_jour(n int, h time default '20:00') returns timestamptz language sql stable as $$
  select (((now() at time zone 'Europe/Paris')::date + n) + h) at time zone 'Europe/Paris'
$$;
create or replace function dm_aujourdhui() returns date language sql stable as $$
  select (now() at time zone 'Europe/Paris')::date
$$;
-- Requête « en tant que » un compte : son résultat, ou l'erreur.
create or replace function dm_lire(p_user uuid, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql into v;
  exception
    when insufficient_privilege then v := 'REFUS';
    when others then v := 'ERR:' || sqlerrm;
  end;
  execute 'reset role';
  return coalesce(v, 'null');
end $$;
-- Création par un compte (destinataire = numéro donné) : l'id, ou l'erreur.
create or replace function dm_creer(p_user uuid, p_dates timestamptz[], p_dest_tel text default '0600000002',
                                    p_extra text default '') returns text language sql as $$
  select dm_lire(p_user, format(
    $q$insert into pactes (type, statut, dates_proposees, restaurant_id, initiateur_id, initiateur_nom,
       destinataire_nom, destinataire_telephone %s) values ('diner', 'enAttenteChoixDateDestinataire', %L,
       '00000000-0000-0000-0000-0000000000aa', %L, 'X', 'Y', %L %s) returning id::text$q$,
    case when p_extra = '' then '' else ', date_minimale' end, p_dates, p_user, p_dest_tel,
    case when p_extra = '' then '' else ', ' || quote_literal(p_extra) end))
$$;
-- Contre-proposition par un compte : 'OK' ou l'erreur.
create or replace function dm_contre(p_user uuid, p uuid, p_dates timestamptz[], p_statut text) returns text language sql as $$
  select dm_lire(p_user, format(
    $q$update pactes set dates_proposees = %L, nombre_echanges_date = nombre_echanges_date + 1, statut = %L
       where id = %L returning 'OK'$q$, p_dates, p_statut, p))
$$;
-- Choix de la date par le destinataire : 'OK' ou l'erreur.
create or replace function dm_choisir(p_user uuid, p uuid, p_date timestamptz) returns text language sql as $$
  select dm_lire(p_user, format(
    $q$update pactes set date_retenue = %L, statut = 'enAttenteReponse' where id = %L returning 'OK'$q$, p_date, p))
$$;
create or replace function dm_min(p uuid) returns text language sql as $$
  select coalesce(date_minimale::text, 'null') from pactes where id = p
$$;

-- ===================================================================
-- A. Création par un utilisateur standard
-- ===================================================================
select verifier('A', 'J+14 (20h, Paris) : refusé (date_trop_proche)',
  dm_creer(:'E', array[dm_jour(14)]) like '%date_trop_proche%', dm_creer(:'E', array[dm_jour(14)]));
select verifier('A', 'J+14 à 23h30 heure de Paris : refusé (le jour de Paris compte)',
  dm_creer(:'E', array[dm_jour(14, '23:30')]) like '%date_trop_proche%');
select dm_creer(:'E', array[dm_jour(15, '00:30')]) as a \gset
select verifier('A', 'J+15 à 00h30 heure de Paris : accepté', :'a' ~ '^[0-9a-f-]{36}$', :'a');
select verifier('A', 'date_minimale posée par le serveur : aujourd''hui (Paris) + 15',
  dm_min(:'a') = (dm_aujourdhui() + 15)::text, dm_min(:'a'));
select verifier('A', 'une seule date trop proche parmi plusieurs : tout est refusé',
  dm_creer(:'E', array[dm_jour(20), dm_jour(14)]) like '%date_trop_proche%');
select dm_creer(:'E', array[dm_jour(30)], '0600000002', '2000-01-01') as a2 \gset
select verifier('A', 'date_minimale envoyée par l''app : ignorée, recalculée par le serveur',
  dm_min(:'a2') = (dm_aujourdhui() + 15)::text, :'a2' || ' → ' || dm_min(:'a2'));
select verifier('A', 'date retenue fournie à la création, trop proche : refusée',
  dm_lire(:'E', format($q$insert into pactes (type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id,
     initiateur_nom, destinataire_nom, destinataire_telephone) values ('diner', 'enAttenteReponse', %L, %L,
     '00000000-0000-0000-0000-0000000000aa', %L, 'X', 'Y', '0600000002') returning 'OK'$q$,
     array[dm_jour(20)], dm_jour(5), :'E')) like '%date_trop_proche%');

-- ===================================================================
-- B. Comptes fondateurs : email confirmé de auth.users uniquement
-- ===================================================================
select dm_creer(:'F', array[dm_jour(2)]) as b \gset
select verifier('B', 'fondateur (email confirmé, casse ignorée) : J+2 accepté, Swend exempté',
  :'b' ~ '^[0-9a-f-]{36}$' and dm_min(:'b') = 'null', :'b');
select verifier('B', 'fondateur à l''email non confirmé : soumis à la règle',
  dm_creer(:'N', array[dm_jour(2)]) like '%date_trop_proche%');
select verifier('B', 'profiles.email d''un fondateur modifiable par l''utilisateur… mais ignoré',
  dm_lire(:'P', format($q$update profiles set email = 'kevinarner@hotmail.com' where id = %L returning 'OK'$q$, :'P')) = 'OK'
  and dm_creer(:'P', array[dm_jour(2)]) like '%date_trop_proche%');
select verifier('B', 'première date possible : standard = aujourd''hui + 15, fondateur = aucune',
  dm_lire(:'E', 'select date_minimale_nouveau_swend()::text') = (dm_aujourdhui() + 15)::text
  and dm_lire(:'F', 'select date_minimale_nouveau_swend()::text') = 'null'
  and dm_lire(:'P', 'select date_minimale_nouveau_swend()::text') = (dm_aujourdhui() + 15)::text);
select verifier('B', 'aucune fonction ne permet de tester l''exemption d''un autre compte',
  (select pronargs = 0 from pg_proc where oid = 'public.date_minimale_nouveau_swend()'::regprocedure)
  and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.prosrc ilike '%comptes_fondateurs%' and p.pronargs > 0
                    and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select verifier('B', 'comptes_fondateurs et auth.users illisibles par l''app',
  dm_lire(:'E', 'select count(*)::text from comptes_fondateurs') = 'REFUS'
  and dm_lire(:'E', 'select count(*)::text from auth.users') = 'REFUS'
  and dm_lire(:'E', 'select count(*)::text from pactes p where exists (select 1 from comptes_fondateurs)') = 'REFUS');

-- ===================================================================
-- C. Contre-propositions : la date minimale du Swend s'applique à tous
-- ===================================================================
select verifier('C', 'Swend standard : contre-proposition à J+14 refusée',
  dm_contre(:'D', :'a', array[dm_jour(14)], 'enAttenteChoixDateInitiateur') like '%date_trop_proche%');
select verifier('C', 'Swend standard : contre-proposition à J+16 acceptée, date minimale inchangée',
  dm_contre(:'D', :'a', array[dm_jour(16)], 'enAttenteChoixDateInitiateur') = 'OK'
  and dm_min(:'a') = (dm_aujourdhui() + 15)::text);
select verifier('C', 'Swend créé par un fondateur : contre-proposition de David (standard) à J+2 acceptée',
  dm_contre(:'D', :'b', array[dm_jour(2)], 'enAttenteChoixDateInitiateur') = 'OK');
select dm_creer(:'E', array[dm_jour(20)], '0611000021') as c3 \gset
select verifier('C', 'Swend créé par Eliot (standard) avec un fondateur : sa contre-proposition à J+2 refusée',
  dm_contre(:'F', :'c3', array[dm_jour(2)], 'enAttenteChoixDateInitiateur') like '%date_trop_proche%');

-- ===================================================================
-- D. Date retenue
-- ===================================================================
select dm_creer(:'E', array[dm_jour(20)]) as d \gset
select verifier('D', 'date retenue à J+14 (hors propositions) : refusée',
  dm_choisir(:'D', :'d', dm_jour(14)) like '%date_trop_proche%');
select verifier('D', 'date retenue à J+20 : acceptée', dm_choisir(:'D', :'d', dm_jour(20)) = 'OK');

-- ===================================================================
-- E. date_minimale jamais modifiable par l'app
-- ===================================================================
select verifier('E', 'l''app ne peut ni effacer ni changer la date minimale (modification_interdite)',
  dm_lire(:'E', format($q$update pactes set date_minimale = null where id = %L returning 'OK'$q$, :'a2')) ~ '(modification_interdite|REFUS)'
  and dm_lire(:'E', format($q$update pactes set date_minimale = '2000-01-01' where id = %L returning 'OK'$q$, :'a2')) ~ '(modification_interdite|REFUS)'
  and dm_min(:'a2') = (dm_aujourdhui() + 15)::text);

-- ===================================================================
-- F. Pas de rétroactivité ; SQL Editor non concerné
-- ===================================================================
insert into pactes (id, type, statut, dates_proposees, restaurant_id, initiateur_id, initiateur_nom,
                    destinataire_nom, destinataire_telephone)
values ('00000000-0000-0000-0000-000000000f01', 'diner', 'enAttenteChoixDateDestinataire', array[dm_jour(3)],
        '00000000-0000-0000-0000-0000000000aa', :'E', 'X', 'Y', '0600000002');
select verifier('F', 'Swend inséré hors app (SQL Editor) : aucune date minimale, date proche acceptée',
  dm_min('00000000-0000-0000-0000-000000000f01') = 'null');
select verifier('F', 'Swend existant sans date minimale : contre-proposition proche acceptée (pas de rétroactivité)',
  dm_contre(:'D', '00000000-0000-0000-0000-000000000f01', array[dm_jour(4)], 'enAttenteChoixDateInitiateur') = 'OK');

-- ===================================================================
-- G. Autres règles inchangées
-- ===================================================================
select dm_creer(:'E', array[dm_jour(20)]) as g \gset
select verifier('G', 'limite de 2 contre-propositions inchangée (3e : negociation_terminee, même avec des dates proches)',
  dm_contre(:'D', :'g', array[dm_jour(21)], 'enAttenteChoixDateInitiateur') = 'OK'
  and dm_contre(:'E', :'g', array[dm_jour(22)], 'enAttenteChoixDateDestinataire') = 'OK'
  and dm_contre(:'D', :'g', array[dm_jour(23)], 'enAttenteChoixDateInitiateur') like '%negociation_terminee%'
  and dm_contre(:'D', :'g', array[dm_jour(2)], 'enAttenteChoixDateInitiateur') like '%negociation_terminee%');
select verifier('G', 'Swend scellé avec une date passée : toujours swend_passe (garde existant en premier)',
  dm_lire(:'E', format($q$insert into pactes (type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id,
     initiateur_nom, destinataire_nom, destinataire_telephone) values ('diner', 'confirme', %L, %L,
     '00000000-0000-0000-0000-0000000000aa', %L, 'X', 'Y', '0600000002') returning 'OK'$q$,
     array[now() - interval '1 hour'], now() - interval '1 hour', :'E')) like '%swend_passe%');
select verifier('G', 'numéro invalide : toujours telephone_invalide',
  dm_creer(:'E', array[dm_jour(2)], '0123') like '%telephone_invalide%');

select case when ok then 'PASS' else 'FAIL' end as r, scenario, verif, detail from test_resultats order by id;
