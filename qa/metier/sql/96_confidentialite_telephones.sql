-- Confidentialité des numéros de téléphone (D-024). Utilise les outils de
-- 10_imprevu.sql (verifier, en_tant_que).
-- Règle : un numéro n'est jamais accessible simplement parce qu'on peut lire
-- un Swend. Une personne de confiance n'obtient jamais le numéro de l'autre
-- titulaire ; celui de son propre titulaire passe uniquement par
-- telephone_titulaire_accessible(), selon ses droits du moment.
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'

-- ---------- personnes ----------
-- Côté Eliot (initiateur) : Kevin prévu, Camille sollicitée, Thomas
-- sélectionné, Rita refusée, Samir désisté, Xavier retiré, Tom sans compte.
-- Côté David (destinataire) : Léa prévue, Marc sélectionné (double
-- remplacement). Zoé : utilisatrice extérieure.
insert into profiles (id, prenom, nom, telephone) values
 ('00000000-0000-0000-0000-00000000000e', 'Eliot', 'E', '0600000001'),
 ('00000000-0000-0000-0000-00000000000d', 'David', 'D', '0600000002'),
 ('00000000-0000-0000-0000-00000000000a', 'Kevin', 'Arner', '0600000003'),
 ('00000000-0000-0000-0000-00000000000c', 'Camille', 'Martin', '0600000004'),
 ('00000000-0000-0000-0000-00000000000b', 'Thomas', 'Dupont', '0600000005'),
 ('00000000-0000-0000-0000-00000000000f', 'Zoe', 'Z', '0600000006'),
 ('00000000-0000-0000-0000-000000000241', 'Rita', 'R', '0611000011'),
 ('00000000-0000-0000-0000-000000000242', 'Samir', 'S', '0611000012'),
 ('00000000-0000-0000-0000-000000000243', 'Xavier', 'X', '0611000013'),
 ('00000000-0000-0000-0000-000000000244', 'Lea', 'L', '0611000014'),
 ('00000000-0000-0000-0000-000000000245', 'Marc', 'M', '0611000015')
on conflict do nothing;

-- ---------- outils ----------
-- Annuaire de test (numéro canonique → prénom), lisible pendant les lectures
-- « en tant que » : sert seulement à nommer les numéros obtenus.
create table if not exists c_annuaire (numero text primary key, prenom text);
truncate c_annuaire;
insert into c_annuaire select telephone_e164, prenom from profiles where telephone_e164 is not null
  on conflict do nothing;
insert into c_annuaire values (normaliser_telephone('0711000016'), 'Tom') on conflict do nothing;
grant select on c_annuaire to authenticated;
create or replace function c_nom(p text) returns text language sql stable as $$
  select coalesce((select prenom from c_annuaire where numero = normaliser_telephone(p)), '?')
$$;
grant execute on function c_nom(text) to authenticated;

-- Résultat texte d'une requête lancée par un utilisateur (RLS et privilèges
-- appliqués) ; 'REFUS' si la base refuse la lecture de la colonne.
create or replace function c_lire(p_user uuid, p_sql text) returns text language plpgsql as $$
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
  return v;
end $$;

-- Swend Eliot / David dans l'état demandé.
create or replace function c_swend(p_etat text) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, type, date_retenue, dates_proposees, restaurant_id, initiateur_id,
                      initiateur_nom, destinataire_nom, destinataire_telephone)
  values (case when p_etat = 'non_scelle' then 'enAttenteReponse' else 'confirme' end, 'diner',
          now() + interval '10 days', to_jsonb(array[now() + interval '10 days']),
          '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-00000000000e', 'Eliot E',
          'David D', '06 00 00 00 02')
  returning id into v;
  insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values
    (v, 'initiateur', 'Kevin', 'Arner', '0600000003', ''),
    (v, 'initiateur', 'Tom', 'T', '0711000016', ''),
    (v, 'initiateur', 'Xavier', 'X', '0611000013', '');
  update remplacants set retire_le = now() where pacte_id = v and prenom = 'Xavier';
  if p_etat = 'non_scelle' then return v; end if;

  insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values
    (v, 'initiateur', 'Camille', 'Martin', '0600000004', ''),
    (v, 'initiateur', 'Thomas', 'Dupont', '0600000005', ''),
    (v, 'initiateur', 'Rita', 'R', '0611000011', ''),
    (v, 'initiateur', 'Samir', 'S', '0611000012', ''),
    (v, 'destinataire', 'Lea', 'L', '0611000014', '');
  update remplacants set demande_statut = 'envoyee' where pacte_id = v and prenom = 'Camille';
  update remplacants set demande_statut = 'refusee' where pacte_id = v and prenom = 'Rita';
  update remplacants set demande_statut = 'desistee' where pacte_id = v and prenom = 'Samir';
  update remplacants set demande_statut = 'acceptee', selectionne = true where pacte_id = v and prenom = 'Thomas';

  if p_etat = 'apres_h' then
    perform qa.deplacer_swend(v, now() - interval '1 hour');
  elsif p_etat = 'annule' then
    update pactes set statut = 'annule' where id = v;
  elsif p_etat = 'double' then
    insert into remplacants (pacte_id, cote, prenom, nom, telephone, email)
      values (v, 'destinataire', 'Marc', 'M', '0611000015', '');
    update remplacants set demande_statut = 'acceptee', selectionne = true
      where pacte_id = v and prenom = 'Marc';
  end if;
  return v;
end $$;

-- Tous les numéros qu'un utilisateur peut obtenir sur ce Swend (autres que le
-- sien) : fiches lisibles, et numéro renvoyé par la fonction du titulaire,
-- essayée sur TOUTES les fiches du Swend.
create or replace function c_numeros(p_user uuid, p_pacte uuid) returns text language plpgsql as $$
declare v_fiches text; v_rpc text := ''; t text; f record; v_moi text;
begin
  select prenom into v_moi from profiles where id = p_user;
  v_fiches := c_lire(p_user, format(
    'select string_agg(c_nom(telephone), '','' order by c_nom(telephone)) from (select telephone from remplacants where pacte_id = %L) s',
    p_pacte));
  for f in select id from remplacants where pacte_id = p_pacte order by id loop
    t := c_lire(p_user, format('select c_nom(telephone_titulaire_accessible(%L))', f.id));
    if t is not null and t <> '?' then v_rpc := v_rpc || case when v_rpc = '' then '' else ',' end || t; end if;
  end loop;
  -- Son propre numéro (sa propre fiche) n'est pas une exposition.
  v_fiches := nullif(array_to_string(array_remove(string_to_array(coalesce(v_fiches, ''), ','), v_moi), ','), '');
  return 'fiches=[' || coalesce(v_fiches, '') || '] titulaire=[' || v_rpc || ']';
end $$;

create temp table c_roles (o int, role text, u uuid);
insert into c_roles values
 (1, 'initiateur', '00000000-0000-0000-0000-00000000000e'),
 (2, 'destinataire', '00000000-0000-0000-0000-00000000000d'),
 (3, 'prévu (Kevin)', '00000000-0000-0000-0000-00000000000a'),
 (4, 'sollicitée (Camille)', '00000000-0000-0000-0000-00000000000c'),
 (5, 'sélectionné (Thomas)', '00000000-0000-0000-0000-00000000000b'),
 (6, 'refusée (Rita)', '00000000-0000-0000-0000-000000000241'),
 (7, 'désisté (Samir)', '00000000-0000-0000-0000-000000000242'),
 (8, 'retiré (Xavier)', '00000000-0000-0000-0000-000000000243'),
 (9, 'prévue côté David (Léa)', '00000000-0000-0000-0000-000000000244'),
 (10, 'sélectionné côté David (Marc)', '00000000-0000-0000-0000-000000000245'),
 (11, 'extérieure (Zoé)', '00000000-0000-0000-0000-00000000000f');

-- Attendu : état × rôle → numéros obtenables (hors le sien).
create temp table c_attendu (etat text, o int, attendu text);
insert into c_attendu
select e.etat, r.o, case
  -- Titulaires : les personnes de leur côté (numéros qu'ils ont saisis).
  when r.o = 1 and e.etat = 'non_scelle' then 'fiches=[Kevin,Tom,Xavier] titulaire=[]'
  when r.o = 1 then 'fiches=[Camille,Kevin,Rita,Samir,Thomas,Tom,Xavier] titulaire=[]'
  when r.o = 2 and e.etat = 'non_scelle' then 'fiches=[] titulaire=[]'
  when r.o = 2 and e.etat = 'double' then 'fiches=[Lea,Marc] titulaire=[]'
  when r.o = 2 then 'fiches=[Lea] titulaire=[]'
  -- Avant H, sur un Swend scellé en cours : chaque personne non retirée
  -- obtient SON titulaire, par la fonction dédiée uniquement.
  when e.etat = 'scelle_avant_h' and r.o in (3, 4, 5, 6, 7) then 'fiches=[] titulaire=[Eliot]'
  when e.etat = 'scelle_avant_h' and r.o = 9 then 'fiches=[] titulaire=[David]'
  -- Après H, annulation, double remplacement : seul le sélectionné.
  when e.etat in ('apres_h', 'annule', 'double') and r.o = 5 then 'fiches=[] titulaire=[Eliot]'
  when e.etat = 'double' and r.o = 10 then 'fiches=[] titulaire=[David]'
  else 'fiches=[] titulaire=[]'
end
from (values ('non_scelle'), ('scelle_avant_h'), ('apres_h'), ('annule'), ('double')) e(etat), c_roles r;

create temp table c_obtenu (etat text, o int, obtenu text, pactes_tel text, pactes_tout text, statut text);
do $$
declare e text; v uuid; r record;
begin
  foreach e in array array['non_scelle', 'scelle_avant_h', 'apres_h', 'annule', 'double'] loop
    v := c_swend(e);
    for r in select * from c_roles order by o loop
      insert into c_obtenu values (e, r.o, c_numeros(r.u, v),
        c_lire(r.u, format('select string_agg(destinataire_telephone, '','') from pactes where id = %L', v)),
        c_lire(r.u, format('select count(*)::text from (select * from pactes where id = %L) s', v)),
        (select statut || case when date_retenue > now() then '' else '+passé' end from pactes where id = v));
    end loop;
  end loop;
end $$;

-- ===================================================================
-- A. Matrice rôles × états : numéros obtenables
-- ===================================================================
select verifier('A', 'états construits : non scellé, scellé, passé, annulé, double remplacement',
  (select string_agg(distinct statut, ',' order by statut) from c_obtenu)
    = 'annule,annuleDoubleAbsence,confirme,confirme+passé,enAttenteReponse',
  (select string_agg(distinct statut, ',' order by statut) from c_obtenu));

select verifier('A', a.etat || ' — ' || r.role || ' : ' || a.attendu, o.obtenu = a.attendu, o.obtenu)
from c_attendu a join c_obtenu o using (etat, o) join c_roles r using (o)
order by a.etat, a.o;

-- ===================================================================
-- B. La ligne Swend ne donne plus aucun numéro, à personne
-- ===================================================================
select verifier('B', 'pactes.destinataire_telephone illisible pour tous les rôles, dans tous les états',
  not exists (select 1 from c_obtenu where pactes_tel is distinct from 'REFUS'),
  (select string_agg(etat || '/' || o || '=' || coalesce(pactes_tel, 'null'), ' ')
   from c_obtenu where pactes_tel is distinct from 'REFUS'));
select verifier('B', '« select * » sur pactes refusé à l''app (aucune colonne non accordée ne sort)',
  not exists (select 1 from c_obtenu where pactes_tout is distinct from 'REFUS'),
  (select string_agg(distinct pactes_tout, ' ') from c_obtenu));
select verifier('B', 'une personne de confiance côté Eliot n''obtient jamais le numéro de David (fiches, fonction, ligne Swend)',
  not exists (select 1 from c_obtenu where o between 3 and 8
              and (obtenu like '%David%' or coalesce(pactes_tel, '') like '%06 00 00 00 02%')),
  (select string_agg(etat || '/' || o, ' ') from c_obtenu where o between 3 and 8
     and (obtenu like '%David%' or coalesce(pactes_tel, '') like '%06 00 00 00 02%')));
select verifier('B', 'une personne de confiance côté David n''obtient jamais le numéro d''Eliot',
  not exists (select 1 from c_obtenu where o in (9, 10) and obtenu like '%Eliot%'));
select verifier('B', 'le destinataire n''obtient jamais le numéro de l''initiateur (ni l''inverse hors saisie)',
  not exists (select 1 from c_obtenu where o = 2 and obtenu like '%Eliot%')
  and not exists (select 1 from c_obtenu where o = 1 and obtenu like '%David%'));
select verifier('B', 'utilisatrice extérieure et personne retirée : aucun numéro',
  not exists (select 1 from c_obtenu where o in (8, 11) and obtenu <> 'fiches=[] titulaire=[]'));
select verifier('B', 'la ligne Swend reste lisible (colonnes relues par l''app) pour ses titulaires',
  c_lire(:'E', 'select count(*)::text from (select id, type, statut, dates_proposees, date_retenue, nombre_echanges_date, restaurant_id, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, created_at from pactes) s') ~ '^[1-9]'
  and c_lire(:'D', 'select count(*)::text from (select id, type, statut, dates_proposees, date_retenue, nombre_echanges_date, restaurant_id, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, created_at from pactes) s') ~ '^[1-9]');

-- ===================================================================
-- C. Création d'un Swend : le numéro s'écrit toujours
-- ===================================================================
select verifier('C', 'Eliot crée un Swend (réponse limitée aux colonnes de l''app)',
  c_lire(:'E', $q$with n as (insert into pactes (type, statut, dates_proposees, restaurant_id, initiateur_id,
      initiateur_nom, destinataire_nom, destinataire_telephone)
    values ('diner', 'enAttenteChoixDateDestinataire', to_jsonb(array[now() + interval '20 days']),
      '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-00000000000e', 'Eliot E', 'David D',
      '06.00.00.00.02 ')
    returning id, type, statut, dates_proposees, date_retenue, nombre_echanges_date, restaurant_id,
      initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, created_at)
    select 'OK' from n$q$) = 'OK');
select verifier('C', 'le numéro saisi est enregistré, le destinataire rattaché par la base',
  (select destinataire_telephone = '06.00.00.00.02 ' and destinataire_telephone_e164 = '+33600000002'
          and destinataire_id = :'D'
   from pactes where initiateur_id = :'E' and (instants_proposes(dates_proposees))[1] > now() + interval '19 days'
   order by created_at desc limit 1));
select verifier('C', 'demander le numéro en retour de la création est refusé',
  c_lire(:'E', $q$with n as (insert into pactes (type, statut, dates_proposees, restaurant_id, initiateur_id,
      initiateur_nom, destinataire_nom, destinataire_telephone)
    values ('diner', 'enAttenteChoixDateDestinataire', to_jsonb(array[now() + interval '21 days']),
      '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-00000000000e', 'Eliot E', 'David D',
      '0600000002') returning destinataire_telephone)
    select 'OK' from n$q$) = 'REFUS');

-- ===================================================================
-- D. Privilèges : listes blanches (toute nouvelle exposition fait échouer)
-- ===================================================================
select verifier('D', 'colonnes téléphone lisibles par l''app : seulement profiles (sa ligne) et remplacants (RLS)',
  (select coalesce(string_agg(table_name || '.' || column_name, ',' order by table_name, column_name), '')
   from information_schema.columns
   where table_schema = 'public' and column_name ~* 'telephone|phone'
     and (has_column_privilege('authenticated', format('public.%I', table_name), column_name, 'select')
          or has_column_privilege('anon', format('public.%I', table_name), column_name, 'select')))
  = 'profiles.telephone,profiles.telephone_e164,remplacants.telephone,remplacants.telephone_e164',
  (select string_agg(table_name || '.' || column_name, ',' order by table_name, column_name)
   from information_schema.columns
   where table_schema = 'public' and column_name ~* 'telephone|phone'
     and (has_column_privilege('authenticated', format('public.%I', table_name), column_name, 'select')
          or has_column_privilege('anon', format('public.%I', table_name), column_name, 'select'))));
select verifier('D', 'numéro du destinataire : écriture à la création conservée, lecture retirée',
  has_column_privilege('authenticated', 'public.pactes', 'destinataire_telephone', 'insert')
  and not has_column_privilege('authenticated', 'public.pactes', 'destinataire_telephone', 'select')
  and not has_column_privilege('authenticated', 'public.pactes', 'destinataire_telephone_e164', 'select')
  and not has_table_privilege('authenticated', 'public.pactes', 'select'));
select verifier('D', 'fonctions SECURITY DEFINER exécutables par l''app qui touchent un numéro : liste blanche',
  (select string_agg(p.proname, ',' order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
     and p.prosrc ~* 'telephone|phone')
  = 'ajouter_et_demander_remplacement,creer_swend_depuis_chat,destinataire_a_un_compte,telephone_titulaire_accessible',
  (select string_agg(p.proname, ',' order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
     and p.prosrc ~* 'telephone|phone'));
select verifier('D', 'retours de ces fonctions : un seul numéro possible (telephone_titulaire_accessible)',
  pg_get_function_result('public.ajouter_et_demander_remplacement(uuid, text, text, text, text)'::regprocedure) = 'uuid'
  -- D-023c : recopie le numéro du profil dans le Swend, ne renvoie que son id.
  and pg_get_function_result('public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb)'::regprocedure) = 'uuid'
  and pg_get_function_result('public.destinataire_a_un_compte(text)'::regprocedure) = 'boolean'
  and pg_get_function_result('public.telephone_titulaire_accessible(uuid)'::regprocedure) = 'text');
select verifier('D', 'anciennes fonctions à numéro non exécutables par l''app',
  not has_function_privilege('authenticated', 'public.telephone_titulaire_du_pacte(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.trouver_profil_par_telephone(text)', 'execute'));
select verifier('D', 'vues publiques contenant un numéro : fermées à l''app',
  not exists (select 1 from information_schema.columns c
              join pg_class k on k.relname = c.table_name and k.relkind = 'v'
              join pg_namespace n on n.oid = k.relnamespace and n.nspname = 'public'
              where c.table_schema = 'public' and c.column_name ~* 'telephone|phone'
                and (has_column_privilege('authenticated', format('public.%I', c.table_name), c.column_name, 'select')
                     or has_column_privilege('anon', format('public.%I', c.table_name), c.column_name, 'select'))));

-- ===================================================================
-- E. Notifications : aucun numéro dans les push (tous les tests précédents)
-- ===================================================================
select verifier('E', 'aucune push ne contient de numéro (titre, texte, données)',
  not exists (
    select 1 from notifications_log n,
      lateral (select regexp_replace(coalesce(n.titre, '') || ' ' || coalesce(n.corps, '') || ' ' || coalesce(n.data::text, ''),
                 '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '', 'gi') as t) x
    where x.t ~ '(\+|00)[0-9]{2}[ .]?[0-9]([ .-]?[0-9]){7,}' or x.t ~ '0[1-9]([ .-]?[0-9]){8}'
       or n.data ?| array['telephone', 'telephone_interlocuteur', 'phone']),
  (select count(*)::text || ' push(s) totales' from notifications_log));

-- ===================================================================
-- F. Risque résiduel accepté en V1 (documenté) : un titulaire peut
-- confirmer qu'un numéro qu'il devine est celui de l'autre titulaire
-- (refus « personne_est_participant » à l'ajout d'une personne de confiance).
-- ===================================================================
select verifier('F', 'oracle personne_est_participant : comportement connu, accepté pour la V1',
  en_tant_que(:'D', format(
    'insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, ''destinataire'', ''X'', ''Y'', ''06 00 00 00 01'', '''')',
    (select id from pactes where initiateur_id = :'E' and statut = 'confirme' and date_retenue > now()
     order by created_at desc limit 1))) like '%personne_est_participant%');

select case when ok then 'PASS' else 'FAIL' end as r, scenario, verif, detail from test_resultats order by id;
