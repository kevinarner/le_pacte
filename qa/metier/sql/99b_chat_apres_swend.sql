-- Chat après le Swend (D-023b). Utilise les outils de 10_imprevu.sql
-- (verifier, en_tant_que, compter_en_tant_que). Tous les Swends de cette
-- suite sont datés en 2031 et le moteur est appelé avec un instant contrôlé ;
-- la mise en service est placée au 1er janvier 2031 pour qu'aucun Swend des
-- autres suites (datés d'aujourd'hui) n'ouvre de chat ici.
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set T '00000000-0000-0000-0000-00000000000b'
\set Z '00000000-0000-0000-0000-00000000000f'
\set R '00000000-0000-0000-0000-000000000241'
\set S '00000000-0000-0000-0000-000000000242'
\set X '00000000-0000-0000-0000-000000000243'
\set M '00000000-0000-0000-0000-000000000245'

insert into profiles (id, prenom, nom, telephone) values
 ('00000000-0000-0000-0000-000000000241', 'Rita', 'R', '0611000011'),
 ('00000000-0000-0000-0000-000000000242', 'Samir', 'S', '0611000012'),
 ('00000000-0000-0000-0000-000000000243', 'Xavier', 'X', '0611000013'),
 ('00000000-0000-0000-0000-000000000245', 'Marc', 'M', '0611000015')
on conflict do nothing;
update chat_apres_swend_service set mise_en_service = '2031-01-01 00:00+00';

-- ---------- outils ----------
create or replace function cs_swend(p_date timestamptz, p_statut text default 'confirme') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, type, date_retenue, dates_proposees, restaurant_id, initiateur_id,
                      initiateur_nom, destinataire_nom, destinataire_telephone)
  values (p_statut, 'diner', p_date, array[p_date], '00000000-0000-0000-0000-0000000000aa',
          '00000000-0000-0000-0000-00000000000e', 'Eliot E', 'David D', '06 00 00 00 02')
  returning id into v;
  return v;
end $$;
-- Fiche dans un état donné (null, envoyee, refusee, desistee, acceptee+sel, retiree).
create or replace function cs_fiche(p uuid, p_cote text, p_prenom text, p_tel text, p_etat text default null)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into remplacants (pacte_id, cote, prenom, nom, telephone, email)
  values (p, p_cote, p_prenom, 'N', p_tel, '') returning id into v;
  if p_etat = 'retiree' then
    update remplacants set retire_le = now() where id = v;
  elsif p_etat = 'selectionne' then
    update remplacants set demande_statut = 'acceptee', selectionne = true where id = v;
  elsif p_etat is not null then
    update remplacants set demande_statut = p_etat where id = v;
  end if;
  return v;
end $$;
create or replace function cs_chat(p uuid) returns uuid language sql as $$
  select id from chats_apres_swend where pacte_id = p
$$;
create or replace function cs_participants(p uuid) returns text language sql as $$
  select coalesce(string_agg(a.role || coalesce('(' || a.place_de || ')', '') || ':' || a.prenom_affiche, ','
                  order by a.role), '')
  from participants_chat_apres_swend a join chats_apres_swend c on c.id = a.chat_id where c.pacte_id = p
$$;
create or replace function cs_n0() returns bigint language sql as $$
  select coalesce(max(id), 0) from notifications_log
$$;
-- Push d'un Swend depuis n0 : « Prénom|titre|texte », triées.
create or replace function cs_push(p_n0 bigint, p uuid) returns text language sql as $$
  select coalesce(string_agg(coalesce(pr.prenom, '?') || '|' || n.titre || '|' || n.corps, ' ## '
                  order by pr.prenom, n.id), '')
  from notifications_log n left join profiles pr on pr.id = n.profile_id
  where n.id > p_n0 and n.data->>'pacte_id' = p::text
$$;
-- Lecture « en tant que » renvoyant un texte (RLS appliquée) ; erreurs lisibles.
create or replace function cs_lire(p_user uuid, p_sql text) returns text language plpgsql as $$
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
-- Résumé d'un chat vu par un utilisateur : « non_lus|jamais_ouvert|dernier|participants ».
create or replace function cs_resume(p_user uuid, p_chat uuid) returns text language sql as $$
  select cs_lire(p_user, format(
    $q$select non_lus || '|' || jamais_ouvert || '|' || coalesce(dernier_expediteur, '-') || '|' ||
       (select string_agg(x.v->>'prenom' || case when (x.v->>'est_moi')::boolean then '*' else '' end, '·' order by x.i)
        from jsonb_array_elements(participants) with ordinality x(v, i))
     from mes_chats_apres_swend() where chat_id = %L$q$, p_chat))
$$;
create or replace function cs_envoyer(p_user uuid, p_chat uuid, p_texte text) returns text language sql as $$
  select en_tant_que(p_user, format('select envoyer_message_apres_swend(%L, %L)', p_chat, p_texte))
$$;

-- ===================================================================
-- A. Heure d'ouverture (Europe/Paris, changements d'heure compris)
-- ===================================================================
select verifier('A', h || ' → ' || attendu,
  ouverture_chat_apres_swend(h::timestamptz) = attendu::timestamptz,
  ouverture_chat_apres_swend(h::timestamptz)::text)
from (values
  ('2031-10-13 12:00 Europe/Paris', '2031-10-13 15:00 Europe/Paris'),
  ('2031-10-13 13:00 Europe/Paris', '2031-10-13 16:00 Europe/Paris'),
  ('2031-10-13 19:30 Europe/Paris', '2031-10-13 22:30 Europe/Paris'),
  ('2031-10-13 20:00 Europe/Paris', '2031-10-13 23:00 Europe/Paris'),
  ('2031-10-13 20:01 Europe/Paris', '2031-10-14 10:00 Europe/Paris'),
  ('2031-10-13 20:30 Europe/Paris', '2031-10-14 10:00 Europe/Paris'),
  ('2031-10-13 22:00 Europe/Paris', '2031-10-14 10:00 Europe/Paris'),
  ('2031-12-31 21:00 Europe/Paris', '2032-01-01 10:00 Europe/Paris'),
  -- Heure d'été (dimanche 30 mars 2031) : Swend la veille à 22h → 10h CEST.
  ('2031-03-29 22:00 Europe/Paris', '2031-03-30 08:00+00'),
  ('2031-03-30 20:00 Europe/Paris', '2031-03-30 21:00+00'),
  -- Heure d'hiver (dimanche 26 octobre 2031) : Swend la veille à 22h → 10h CET.
  ('2031-10-25 22:00 Europe/Paris', '2031-10-26 09:00+00'),
  ('2031-10-26 20:00 Europe/Paris', '2031-10-26 22:00+00')
) t(h, attendu);
select verifier('A', 'H+3 = 3 heures réelles (été et hiver)',
  ouverture_chat_apres_swend('2031-07-01 12:00 Europe/Paris') - '2031-07-01 12:00 Europe/Paris'::timestamptz = interval '3 hours'
  and ouverture_chat_apres_swend('2031-01-15 12:00 Europe/Paris') - '2031-01-15 12:00 Europe/Paris'::timestamptz = interval '3 hours');

-- ===================================================================
-- B. Ouverture : Swend 20h, remplaçant final Thomas (après le désistement
--    de Kevin), personnes non choisies jamais participantes
-- ===================================================================
select cs_swend('2031-10-13 20:00 Europe/Paris') as a \gset
select cs_fiche(:'a', 'initiateur', 'Kevin', '0600000003') as fk \gset
update remplacants set demande_statut = 'acceptee', selectionne = true where id = :'fk';
update remplacants set demande_statut = 'desistee', selectionne = false where id = :'fk';
-- Prénom saisi sur la fiche (« Tomtom ») : le chat affichera celui du compte.
select cs_fiche(:'a', 'initiateur', 'Tomtom', '0600000005', 'selectionne') as ft \gset
select cs_fiche(:'a', 'initiateur', 'Camille', '0600000004', 'envoyee') as fc \gset
select cs_fiche(:'a', 'initiateur', 'Rita', '0611000011', 'refusee') as fr \gset
select cs_fiche(:'a', 'initiateur', 'Samir', '0611000012', 'desistee') as fs \gset
select cs_fiche(:'a', 'initiateur', 'Xavier', '0611000013', 'retiree') as fx \gset
select cs_fiche(:'a', 'destinataire', 'Zoe', '0600000006') as fz \gset

select figer_swends_passes('2031-10-13 20:01 Europe/Paris');
select verifier('B', 'Swend figé à H par D-023a (demande de Camille close)',
  exists (select 1 from swends_figes where pacte_id = :'a')
  and (select demande_statut from remplacants where id = :'fc') = 'cloturee');
select cs_n0() as n0 \gset
select ouvrir_chats_apres_swend('2031-10-13 22:59 Europe/Paris');
select verifier('B', 'avant 23:00 : aucun chat, aucune push',
  cs_chat(:'a') is null and cs_push(:'n0', :'a') = '');
select verifier('B', 'avant l''ouverture : aucun chat visible, même pour les titulaires',
  cs_lire(:'E', 'select count(*)::text from chats_apres_swend') = '0'
  and cs_lire(:'E', 'select count(*)::text from mes_chats_apres_swend()') = '0');
select ouvrir_chats_apres_swend('2031-10-13 23:00 Europe/Paris');
select cs_chat(:'a') as ca \gset
select verifier('B', 'à 23:00 : chat ouvert, heure d''ouverture enregistrée',
  :'ca' <> '' and (select ouvre_le = '2031-10-13 23:00 Europe/Paris'::timestamptz and ferme_le is null
                   from chats_apres_swend where id = :'ca'));
select verifier('B', 'participants : Eliot, David, Thomas (prénom du compte, place d''Eliot)',
  cs_participants(:'a') = 'destinataire:David,initiateur:Eliot,remplacant(initiateur):Thomas', cs_participants(:'a'));
select verifier('B', 'jamais participants : Kevin (désisté), Camille, Rita, Samir, Xavier, Zoé',
  not exists (select 1 from participants_chat_apres_swend where chat_id = :'ca'
              and profil_id in (:'K', :'C', :'R', :'S', :'X', :'Z')));
select verifier('B', 'une push « Alors, ce Swend ? » par participant, texte exact',
  cs_push(:'n0', :'a') = 'David|Alors, ce Swend ?|Le silence est levé. Vous pouvez maintenant en reparler dans le chat.'
    || ' ## Eliot|Alors, ce Swend ?|Le silence est levé. Vous pouvez maintenant en reparler dans le chat.'
    || ' ## Thomas|Alors, ce Swend ?|Le silence est levé. Vous pouvez maintenant en reparler dans le chat.',
  cs_push(:'n0', :'a'));
select verifier('B', 'données de la push : type chat_apres_swend, chat_id, pacte_id (rien d''autre)',
  (select bool_and(data->>'type' = 'chat_apres_swend' and data->>'chat_id' = :'ca'
                   and (select count(*) from jsonb_object_keys(data)) = 3)
   from notifications_log where id > :n0 and data->>'pacte_id' = :'a'));
select cs_n0() as n1 \gset
select ouvrir_chats_apres_swend('2031-10-13 23:00 Europe/Paris');
select ouvrir_chats_apres_swend('2031-10-14 08:00 Europe/Paris');
select verifier('B', 'double appel : toujours un seul chat, aucune nouvelle push',
  (select count(*) from chats_apres_swend where pacte_id = :'a') = 1
  and (select count(*) from participants_chat_apres_swend where chat_id = :'ca') = 3
  and cs_push(:'n1', :'a') = '');

-- ===================================================================
-- C. Retard du planificateur : ≤ 12 h → push ; > 12 h → chat sans push
-- ===================================================================
select cs_swend('2031-10-15 12:00 Europe/Paris') as c1 \gset
select cs_swend('2031-10-16 12:00 Europe/Paris') as c2 \gset
select figer_swends_passes('2031-10-17 00:00 Europe/Paris');
select cs_n0() as n0 \gset
select ouvrir_chats_apres_swend('2031-10-16 03:00 Europe/Paris');
select verifier('C', 'retard de 12 h pile : chat ouvert, push envoyée',
  cs_chat(:'c1') is not null and cs_push(:'n0', :'c1') like 'David|Alors, ce Swend ?%', cs_push(:'n0', :'c1'));
select cs_n0() as n0 \gset
select ouvrir_chats_apres_swend('2031-10-17 03:01 Europe/Paris');
select verifier('C', 'retard de 12 h 01 : chat ouvert quand même, sans push tardive',
  cs_chat(:'c2') is not null and cs_participants(:'c2') = 'destinataire:David,initiateur:Eliot'
  and cs_push(:'n0', :'c2') = '', cs_push(:'n0', :'c2'));

-- ===================================================================
-- D. Pas de rattrapage (borne de mise en service)
-- ===================================================================
select cs_swend('2031-11-03 12:00 Europe/Paris') as d1 \gset
select figer_swends_passes('2031-11-03 12:01 Europe/Paris');
update chat_apres_swend_service set mise_en_service = '2031-11-03 16:00 Europe/Paris';
select ouvrir_chats_apres_swend('2031-11-04 12:00 Europe/Paris');
select verifier('D', 'ouverture théorique (15:00) avant la mise en service (16:00) : jamais de chat',
  cs_chat(:'d1') is null);
update chat_apres_swend_service set mise_en_service = '2031-11-03 15:00 Europe/Paris';
select ouvrir_chats_apres_swend('2031-11-04 12:00 Europe/Paris');
select verifier('D', 'ouverture théorique égale à la mise en service : chat ouvert',
  cs_chat(:'d1') is not null);
delete from chat_apres_swend_service;
select cs_swend('2031-11-05 12:00 Europe/Paris') as d2 \gset
select figer_swends_passes('2031-11-05 12:01 Europe/Paris');
select verifier('D', 'sans mise en service enregistrée : le moteur n''ouvre rien',
  ouvrir_chats_apres_swend('2031-11-05 16:00 Europe/Paris') = 0 and cs_chat(:'d2') is null);
insert into chat_apres_swend_service (id, mise_en_service) values (true, '2031-01-01 00:00+00');

-- ===================================================================
-- E. Aucun chat : annulé, double remplacement, non scellé, non figé, maintenu
-- ===================================================================
select cs_swend('2031-11-10 12:00 Europe/Paris') as e_annule \gset
update pactes set statut = 'annule' where id = :'e_annule';
select cs_swend('2031-11-10 12:00 Europe/Paris') as e_double \gset
select cs_fiche(:'e_double', 'initiateur', 'Kevin', '0600000003', 'selectionne') \gset
select cs_fiche(:'e_double', 'destinataire', 'Camille', '0600000004', 'selectionne') \gset
select cs_swend('2031-11-10 12:00 Europe/Paris', 'enAttenteReponse') as e_non_scelle \gset
select cs_swend('2031-11-10 12:00 Europe/Paris', 'maintenu') as e_maintenu \gset
insert into swends_figes (pacte_id, date_retenue) values (:'e_maintenu', '2031-11-10 12:00 Europe/Paris');
select figer_swends_passes('2031-11-10 12:01 Europe/Paris');
select cs_swend('2031-11-10 12:00 Europe/Paris') as e_non_fige \gset
select ouvrir_chats_apres_swend('2031-11-11 12:00 Europe/Paris');
select verifier('E', 'double remplacement : Swend bien annulé par la base',
  (select statut from pactes where id = :'e_double') = 'annuleDoubleAbsence');
select verifier('E', 'aucun chat : annulé, double remplacement, non scellé, maintenu',
  cs_chat(:'e_annule') is null and cs_chat(:'e_double') is null
  and cs_chat(:'e_non_scelle') is null and cs_chat(:'e_maintenu') is null);
select verifier('E', 'aucun chat tant que le Swend n''est pas figé par D-023a',
  cs_chat(:'e_non_fige') is null);
select figer_swends_passes('2031-11-11 12:00 Europe/Paris');
select ouvrir_chats_apres_swend('2031-11-11 12:00 Europe/Paris');
select verifier('E', 'une fois figé : chat ouvert', cs_chat(:'e_non_fige') is not null);

-- ===================================================================
-- F. Participants : remplaçant côté destinataire ; incohérence
-- ===================================================================
select cs_swend('2031-11-12 12:00 Europe/Paris') as f1 \gset
select cs_fiche(:'f1', 'destinataire', 'Kev', '0600000003', 'selectionne') \gset
select cs_swend('2031-11-12 12:00 Europe/Paris') as f2 \gset
select cs_fiche(:'f2', 'initiateur', 'Kevin', '0600000003', 'selectionne') \gset
select cs_fiche(:'f2', 'initiateur', 'Thomas', '0600000005', 'selectionne') \gset
select figer_swends_passes('2031-11-12 12:01 Europe/Paris');
select cs_n0() as n0 \gset
select ouvrir_chats_apres_swend('2031-11-12 15:00 Europe/Paris');
select verifier('F', 'remplaçant côté David : Kevin a pris la place du destinataire',
  cs_participants(:'f1') = 'destinataire:David,initiateur:Eliot,remplacant(destinataire):Kevin', cs_participants(:'f1'));
select verifier('F', 'plus d''un remplaçant actif : chat non ouvert, aucune push',
  cs_chat(:'f2') is null and cs_push(:'n0', :'f2') = '');
select verifier('F', 'anomalie exploitable enregistrée (plusieurs_remplacants_actifs)',
  (select code from anomalies_chat_apres_swend where pacte_id = :'f2') = 'plusieurs_remplacants_actifs');
select ouvrir_chats_apres_swend('2031-11-12 16:00 Europe/Paris');
select verifier('F', 'toujours pas de chat au passage suivant (anomalie à traiter)', cs_chat(:'f2') is null);

-- ===================================================================
-- G. Accès (RLS) : participants seulement, jamais d'écriture directe
-- ===================================================================
select verifier('G', u || ' voit le chat, ses 3 participants',
  cs_lire(u::uuid, format('select count(*)::text from chats_apres_swend where id = %L', :'ca')) = '1'
  and cs_lire(u::uuid, format('select count(*)::text from participants_chat_apres_swend where chat_id = %L', :'ca')) = '3')
from (values (:'E'), (:'D'), (:'T')) v(u);
select verifier('G', 'non-participants (Kevin désisté, Camille, Rita, Samir, Xavier, Zoé, Marc) : rien',
  bool_and(cs_lire(u::uuid, format('select count(*)::text from chats_apres_swend where id = %L', :'ca')) = '0'
           and cs_lire(u::uuid, format('select count(*)::text from participants_chat_apres_swend where chat_id = %L', :'ca')) = '0'
           and cs_lire(u::uuid, format('select count(*)::text from mes_chats_apres_swend() where chat_id = %L', :'ca')) = '0'
           and cs_lire(u::uuid, format('select count(*)::text from messages_apres_swend where chat_id = %L', :'ca')) = '0'))
from (values (:'K'), (:'C'), (:'R'), (:'S'), (:'X'), (:'Z'), (:'M')) v(u);
select verifier('G', 'écriture directe refusée (chat, participants, messages, lectures)',
  cs_lire(:'E', format('insert into messages_apres_swend (chat_id, participant_id, contenu) select %L, id, ''x'' from participants_chat_apres_swend where chat_id = %L and profil_id = %L returning ''OK''', :'ca', :'ca', :'E')) = 'REFUS'
  and cs_lire(:'E', format('update chats_apres_swend set ferme_le = now() where id = %L returning ''OK''', :'ca')) = 'REFUS'
  and cs_lire(:'K', format('insert into participants_chat_apres_swend (chat_id, profil_id, role, prenom_affiche) values (%L, %L, ''remplacant'', ''K'') returning ''OK''', :'ca', :'K')) = 'REFUS'
  and cs_lire(:'E', format('insert into lectures_chat_apres_swend (chat_id, profil_id) values (%L, %L) returning ''OK''', :'ca', :'E')) = 'REFUS');
select verifier('G', 'moteur, anomalies et mise en service inaccessibles à l''app',
  cs_lire(:'E', 'select ouvrir_chats_apres_swend()::text') = 'REFUS'
  and cs_lire(:'E', 'select count(*)::text from anomalies_chat_apres_swend') = 'REFUS'
  and cs_lire(:'E', 'select count(*)::text from chat_apres_swend_service') = 'REFUS');

-- ===================================================================
-- H. Messages : envoi, contrôles, push sans contenu
-- ===================================================================
select cs_n0() as n0 \gset
select verifier('H', 'Thomas écrit (emoji, espaces retirés)',
  cs_envoyer(:'T', :'ca', '  Super soirée 🎉  ') = 'OK');
select verifier('H', 'message enregistré tel quel, sans les espaces, auteur = participant Thomas',
  (select m.contenu = 'Super soirée 🎉' and a.prenom_affiche = 'Thomas' and m.genre = 'texte'
   from messages_apres_swend m join participants_chat_apres_swend a on a.id = m.participant_id
   where m.chat_id = :'ca'));
select verifier('H', 'push aux deux autres seulement, texte exact, sans le contenu',
  cs_push(:'n0', :'a') = 'David|Thomas vous a écrit|Après le Swend · Au Père Lapin'
    || ' ## Eliot|Thomas vous a écrit|Après le Swend · Au Père Lapin', cs_push(:'n0', :'a'));
select verifier('H', 'aucune push ne contient le texte d''un message',
  not exists (select 1 from notifications_log n join messages_apres_swend m
              on (n.titre || n.corps || n.data::text) like '%' || m.contenu || '%'));
select verifier('H', 'message vide ou seulement des espaces : refusé (message_vide)',
  cs_envoyer(:'E', :'ca', '   ') like '%message_vide%' and cs_envoyer(:'E', :'ca', '') like '%message_vide%');
select verifier('H', '2 000 caractères acceptés, 2 001 refusés (message_trop_long)',
  cs_envoyer(:'E', :'ca', repeat('é', 2001)) like '%message_trop_long%'
  and cs_envoyer(:'E', :'ca', repeat('a', 2000)) = 'OK');
select verifier('H', 'non-participants refusés (non_autorise), même avec le bon identifiant',
  cs_envoyer(:'K', :'ca', 'coucou') like '%non_autorise%' and cs_envoyer(:'M', :'ca', 'coucou') like '%non_autorise%'
  and cs_envoyer(:'E', gen_random_uuid(), 'coucou') like '%non_autorise%');
select verifier('H', 'app : pas d''édition ni de suppression des messages',
  cs_lire(:'T', format('update messages_apres_swend set contenu = ''x'' where chat_id = %L returning ''OK''', :'ca')) = 'REFUS'
  and cs_lire(:'T', format('delete from messages_apres_swend where chat_id = %L returning ''OK''', :'ca')) = 'REFUS');

-- ===================================================================
-- I. Non-lus individuels et invitation « Alors, ce Swend ? »
-- ===================================================================
-- État : Thomas (1 message), Eliot (1 message de 2 000 caractères).
select verifier('I', 'David : 2 non lus, jamais ouvert, dernier = Eliot, participants dans l''ordre',
  cs_resume(:'D', :'ca') = '2|true|Eliot|Eliot·David*·Thomas', cs_resume(:'D', :'ca'));
select verifier('I', 'Eliot : 0 non lu (écrire, c''est avoir lu jusque-là), a donc ouvert',
  cs_resume(:'E', :'ca') = '0|false|Eliot|Eliot*·David·Thomas', cs_resume(:'E', :'ca'));
select verifier('I', 'Thomas : 1 non lu (celui d''Eliot)',
  cs_resume(:'T', :'ca') = '1|false|Eliot|Eliot·David·Thomas*', cs_resume(:'T', :'ca'));
select verifier('I', 'David ouvre le chat : lui seul passe à 0 et « déjà ouvert »',
  en_tant_que(:'D', format('select marquer_chat_apres_swend_lu(%L)', :'ca')) = 'OK'
  and cs_resume(:'D', :'ca') = '0|false|Eliot|Eliot·David*·Thomas'
  and cs_resume(:'E', :'ca') = '0|false|Eliot|Eliot*·David·Thomas'
  and cs_resume(:'T', :'ca') = '1|false|Eliot|Eliot·David·Thomas*');
select verifier('I', 'chacun ne lit que sa propre ligne de lecture',
  cs_lire(:'D', format('select count(*)::text from lectures_chat_apres_swend where chat_id = %L', :'ca')) = '1'
  and cs_lire(:'D', format('select string_agg(profil_id::text, '','') from lectures_chat_apres_swend where chat_id = %L', :'ca')) = :'D');
select verifier('I', 'marquer comme lu : refusé aux non-participants',
  en_tant_que(:'K', format('select marquer_chat_apres_swend_lu(%L)', :'ca')) like '%non_autorise%');
select verifier('I', 'le résumé ne contient ni texte de message ni numéro',
  regexp_replace(cs_lire(:'D', 'select coalesce(string_agg(to_jsonb(r)::text, ''''), '''') from mes_chats_apres_swend() r'),
    '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '', 'gi')
    !~ '(Super soirée|aaaa|0[67]([ .]?[0-9]){8}|\+33)');

-- ===================================================================
-- J. Compte supprimé : historique conservé, « Compte supprimé »
-- ===================================================================
update participants_chat_apres_swend set profil_id = null where chat_id = :'ca' and role = 'remplacant';
select verifier('J', 'participant sans compte : affiché « Compte supprimé », messages conservés',
  cs_resume(:'E', :'ca') = '0|false|Eliot|Eliot*·David·Compte supprimé'
  and (select count(*) from messages_apres_swend where chat_id = :'ca') = 2, cs_resume(:'E', :'ca'));
update participants_chat_apres_swend set profil_id = :'T' where chat_id = :'ca' and role = 'remplacant';

-- ===================================================================
-- K. Chat fermé à la main (préparation D-023c) : lecture oui, écriture non
-- ===================================================================
update chats_apres_swend set ferme_le = '2031-10-20 12:00+00', motif_fermeture = 'nouveau_swend' where id = :'ca';
select verifier('K', 'chat fermé : messages toujours lisibles par les participants',
  cs_lire(:'D', format('select count(*)::text from messages_apres_swend where chat_id = %L', :'ca')) = '2'
  and cs_lire(:'D', format('select motif_fermeture from mes_chats_apres_swend() where chat_id = %L', :'ca')) = 'nouveau_swend');
select verifier('K', 'chat fermé : écriture refusée (chat_ferme)',
  cs_envoyer(:'D', :'ca', 'encore un mot') like '%chat_ferme%');
insert into messages_apres_swend (chat_id, genre, contenu)
values (:'ca', 'systeme', 'Un nouveau Swend a été scellé.' || chr(10) || 'Le chat est désormais fermé pour préserver le silence.');
select verifier('K', 'message système possible sans auteur (réservé à D-023c)',
  (select count(*) = 1 from messages_apres_swend where chat_id = :'ca' and genre = 'systeme' and participant_id is null));
select verifier('K', 'un message système ne compte pas comme non lu',
  cs_resume(:'D', :'ca') like '0|false|%', cs_resume(:'D', :'ca'));
select verifier('K', 'un message système doit être sans auteur, un message texte avec auteur',
  not exists (select 1 from messages_apres_swend where (genre = 'systeme') = (participant_id is not null)));

-- ===================================================================
-- L. Confidentialité (D-024) et séparation avec l'imprévu
-- ===================================================================
select verifier('L', 'aucun numéro dans les push du chat',
  not exists (select 1 from notifications_log where data->>'type' = 'chat_apres_swend'
              and (titre || corps || data::text) ~ '(0[67]([ .]?[0-9]){8}|\+33)'));
select verifier('L', 'aucune colonne de numéro dans les tables du chat',
  not exists (select 1 from information_schema.columns where table_schema = 'public'
              and table_name like '%chat_apres_swend%' and column_name ~* 'telephone|phone'));
select verifier('L', 'conversations d''imprévu intactes : aucun message ni lecture ajoutés par le chat',
  not exists (select 1 from messages m join remplacants r on r.id = m.remplacant_id where r.pacte_id = :'a')
  and not exists (select 1 from lectures_fil l join remplacants r on r.id = l.remplacant_id where r.pacte_id = :'a'));

-- ===================================================================
-- M. Temps réel : ajout protégé à la publication (ré-exécution sûre)
-- ===================================================================
select (select mise_en_service from chat_apres_swend_service) as borne_avant \gset
drop publication if exists supabase_realtime;
create publication supabase_realtime;
\o /dev/null
\ir ../../../supabase/migrations/20260930010000_chat_apres_swend.sql
\ir ../../../supabase/migrations/20260930010000_chat_apres_swend.sql
\o
select verifier('M', 'messages du chat ajoutés une fois à supabase_realtime (migration rejouée 2 fois)',
  (select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
   and tablename = 'messages_apres_swend') = 1
  and (select count(*) from pg_publication_tables where pubname = 'supabase_realtime') = 1);
select verifier('M', 'ré-exécution : borne de mise en service inchangée, chats intacts',
  (select mise_en_service from chat_apres_swend_service) = :'borne_avant'::timestamptz
  and (select count(*) from participants_chat_apres_swend where chat_id = :'ca') = 3);
drop publication supabase_realtime;

select case when ok then 'PASS' else 'FAIL' end as r, scenario, verif, detail from test_resultats order by id;
