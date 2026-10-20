-- D-027 (décision d'Eliot du 20/10/2026) : H-3 est la limite ferme pour
-- résoudre un imprévu. Juste avant H-3, à H-3 exactement, après H-3 ;
-- recherche non résolue (un côté, deux côtés, autre côté remplacé),
-- désistement tardif, nouvel imprévu tardif, Swend maintenu, idempotence,
-- rappels, confidentialité, chats et conversations (lot 2 inchangé) ; jobs en
-- échec entre H-3 et H puis reprise après H (gel, chat après le Swend).
-- Utilise les outils de 10_imprevu.sql (verifier, en_tant_que,
-- compter_en_tant_que, statut_fiche, ajouter_fiche), 98_gel_a_h.sql (g_swend,
-- g_dater, g_rpc, g_ecrire, g_codes, g_push, g_n0) et
-- 99g_annulation_conversations.sql (ac_chat, ac_annulation). Swends Eliot
-- (initiateur) / David (destinataire).
-- Instants : chaque appel replace l'heure du Swend par rapport à now() dans
-- sa propre transaction (h3_a, h3_echeance) : « à H-3 exactement » signifie
-- date_retenue = now() + 3 heures pour l'instant de l'appel.
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;

\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set T '00000000-0000-0000-0000-00000000000b'
\set Z '00000000-0000-0000-0000-00000000000f'

-- ---------- outils ----------
-- Place H-3 à now() + p_ecart (0 : H-3 exactement ; positif : H-3 pas encore
-- atteint ; négatif : H-3 passé), puis exécute l'action en tant que p_user.
create or replace function h3_a(p uuid, p_ecart interval, p_user uuid, p_sql text) returns text
language plpgsql as $$
begin
  perform qa.deplacer_swend(p, now() + interval '3 hours' + p_ecart);
  return en_tant_que(p_user, p_sql);
end $$;
create or replace function h3_rpc(p uuid, p_ecart interval, p_user uuid, p_fonction text, p_arg uuid, p_arg2 text default null)
returns text language sql as $$
  select h3_a(p, p_ecart, p_user, case when p_arg2 is null
    then format('select %s(%L)', p_fonction, p_arg)
    else format('select %s(%L, %s)', p_fonction, p_arg, p_arg2) end)
$$;
-- Place H-3 puis lance l'échéance (instant réel) ; renvoie le nombre de
-- Swends annulés parmi ceux de la liste.
create or replace function h3_echeance(p uuid, p_ecart interval) returns int
language plpgsql as $$
begin
  perform qa.deplacer_swend(p, now() + interval '3 hours' + p_ecart);
  perform appliquer_echeances_h3();
  return (select count(*)::int from pactes where id = p and annule_motif = 'echeance_h3');
end $$;
create or replace function h3_declare(p uuid, p_cote text) returns boolean language sql as $$
  select exists (select 1 from imprevus_declares where pacte_id = p and cote = p_cote)
$$;
-- Push reçues par une personne depuis n0 (titre|corps), dans l'ordre.
create or replace function h3_push(p_n0 bigint, p_profil uuid) returns text language sql as $$
  select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '')
  from notifications_log where id > p_n0 and profile_id = p_profil
$$;

-- ===================================================================
-- A. Juste avant H-3 : la recherche reste possible (règle d'avant)
-- ===================================================================
select g_swend(now() + interval '1 day') as pa \gset
select ajouter_fiche(:'E', :'pa', 'initiateur', 'Kevin', '0600000003') as ka \gset
select ajouter_fiche(:'E', :'pa', 'initiateur', 'Camille', '0600000004') as ca \gset
select ajouter_fiche(:'E', :'pa', 'initiateur', 'Thomas', '0600000005') as ta \gset
select verifier('A', 'juste avant H-3 : envoi groupé possible',
  h3_a(:'pa', interval '20 seconds', :'E', format('select count(*) from envoyer_demandes_remplacement(array[%L, %L]::uuid[])', :'ka', :'ca')) = 'OK'
  and statut_fiche(:'ka') = 'envoyee' and statut_fiche(:'ca') = 'envoyee');
select verifier('A', 'juste avant H-3 : refus possible',
  h3_rpc(:'pa', interval '20 seconds', :'C', 'repondre_demande_remplacement', :'ca', 'false') = 'OK' and statut_fiche(:'ca') = 'refusee');
select verifier('A', 'juste avant H-3 : acceptation possible',
  h3_rpc(:'pa', interval '20 seconds', :'K', 'repondre_demande_remplacement', :'ka', 'true') = 'OK' and statut_fiche(:'ka') = 'acceptee+sel');
select verifier('A', 'juste avant H-3 : désistement → recherche rouverte (règle d''avant), Swend maintenu',
  h3_rpc(:'pa', interval '20 seconds', :'K', 'se_desister_du_remplacement', :'ka') = 'OK'
  and statut_fiche(:'ka') = 'desistee' and (select statut from pactes where id = :'pa') = 'confirme'
  and h3_declare(:'pa', 'initiateur'));
select verifier('A', 'juste avant H-3 : ajouter une personne et lui demander possible',
  h3_a(:'pa', interval '20 seconds', :'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)',
    :'pa', 'initiateur', 'Zoé', 'Z', '0600000006')) = 'OK');
select verifier('A', 'juste avant H-3 : « Je peux finalement venir » possible',
  h3_rpc(:'pa', interval '20 seconds', :'E', 'je_peux_finalement_venir', :'pa') = 'OK' and not h3_declare(:'pa', 'initiateur'));
select verifier('A', 'juste avant H-3 : l''échéance ne fait rien (Swend maintenu)',
  h3_echeance(:'pa', interval '20 seconds') = 0 and (select statut from pactes where id = :'pa') = 'confirme');

-- ===================================================================
-- B. À H-3 exactement : plus de recherche ni de réponse ; recherche non
--    résolue → annulation
-- ===================================================================
select g_swend(now() + interval '1 day') as pb \gset
select ajouter_fiche(:'E', :'pb', 'initiateur', 'Kevin', '0600000003') as kb \gset
select ajouter_fiche(:'E', :'pb', 'initiateur', 'Camille', '0600000004') as cb \gset
select ajouter_fiche(:'E', :'pb', 'initiateur', 'Thomas', '0600000005') as tb \gset
select ajouter_fiche(:'D', :'pb', 'destinataire', 'Zoe', '0600000006') as zb \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'kb') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'cb') \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'cb', 'false') \gset
select g_ecrire(:'E', :'kb', 'Tu peux ?') \gset
update reservations_suivi set statut_reservation = 'reservee' where pacte_id = :'pb';
select g_n0() as n0 \gset
select verifier('B', 'H-3 exactement : envoyer une demande → echeance_h3',
  h3_rpc(:'pb', interval '0', :'E', 'envoyer_demande_remplacement', :'tb') like '%echeance_h3%',
  h3_rpc(:'pb', interval '0', :'E', 'envoyer_demande_remplacement', :'tb'));
select verifier('B', 'H-3 exactement : envoi groupé → echeance_h3',
  h3_a(:'pb', interval '0', :'E', format('select count(*) from envoyer_demandes_remplacement(array[%L]::uuid[])', :'tb')) like '%echeance_h3%');
select verifier('B', 'H-3 exactement : ajouter une personne et lui demander → echeance_h3',
  h3_a(:'pb', interval '0', :'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)',
    :'pb', 'initiateur', 'Zoé', 'Z', '0600000006')) like '%echeance_h3%');
select verifier('B', 'H-3 exactement : accepter → echeance_h3',
  h3_rpc(:'pb', interval '0', :'K', 'repondre_demande_remplacement', :'kb', 'true') like '%echeance_h3%');
select verifier('B', 'H-3 exactement : refuser → echeance_h3 (pas de « Personne n’est disponible » trompeur)',
  h3_rpc(:'pb', interval '0', :'K', 'repondre_demande_remplacement', :'kb', 'false') like '%echeance_h3%');
select verifier('B', 'H-3 exactement : « Je peux finalement venir » → echeance_h3',
  h3_rpc(:'pb', interval '0', :'E', 'je_peux_finalement_venir', :'pb') like '%echeance_h3%');
select verifier('B', 'H-3 exactement : annuler une demande (ancienne app) → echeance_h3',
  h3_rpc(:'pb', interval '0', :'E', 'annuler_demande_remplacement', :'kb') like '%echeance_h3%');
select verifier('B', 'refus : rien n''a bougé (fiches, imprévu, aucune push, Swend maintenu)',
  statut_fiche(:'kb') = 'envoyee' and statut_fiche(:'cb') = 'refusee' and statut_fiche(:'tb') = 'null'
  and h3_declare(:'pb', 'initiateur') and (select statut from pactes where id = :'pb') = 'confirme'
  and (select count(*) from notifications_log where id > :n0) = 0
  and (select count(*) from remplacants where pacte_id = :'pb') = 4);
select verifier('B', 'Swend annulé à H-3 exactement (recherche non résolue)', h3_echeance(:'pb', interval '0') = 1);
select verifier('B', 'annulation : statut annule, motif echeance_h3, sans auteur, datée',
  ac_annulation(:'pb') = 'annule|echeance_h3|null|date', ac_annulation(:'pb'));
select verifier('B', 'Eliot : « Le Swend est annulé / Personne n’a pu prendre ta place à temps. »',
  h3_push(:n0, :'E') = 'Le Swend est annulé|Personne n’a pu prendre ta place à temps.', h3_push(:n0, :'E'));
select verifier('B', 'David : « Le Swend est annulé / Eliot ne pourra finalement pas être là. » (aucune coulisse)',
  h3_push(:n0, :'D') = 'Le Swend est annulé|Eliot ne pourra finalement pas être là.', h3_push(:n0, :'D'));
select verifier('B', 'Kevin (en attente) : « Le Swend est annulé / Tu n’as plus besoin de répondre. » ; Camille (refus) et Thomas (prévu) : rien',
  h3_push(:n0, :'K') = 'Le Swend est annulé|Tu n’as plus besoin de répondre.'
  and h3_push(:n0, :'C') = '' and h3_push(:n0, :'T') = '' and h3_push(:n0, :'Z') = '', h3_push(:n0, :'K'));
select verifier('B', 'demande de Kevin close ; refus et personnes prévues inchangés',
  statut_fiche(:'kb') = 'cloturee' and statut_fiche(:'cb') = 'refusee' and statut_fiche(:'tb') = 'null');
select verifier('B', 'aucun rappel envoyé, aucune push pour le restaurant ; suivi interne : « Annuler la réservation au restaurant »',
  not exists (select 1 from notifications_log where id > :n0 and data->>'type' = 'rappel')
  and (select a_faire from reservations_a_suivre where swend_id = :'pb') = 'Annuler la réservation au restaurant',
  (select a_faire from reservations_a_suivre where swend_id = :'pb'));
select verifier('B', 'chat d''annulation entre les deux titulaires (lot 2 inchangé)', ac_chat(:'pb') = 'annulation');
select verifier('B', 'conversation Eliot–Kevin conservée et écrivable (P1) ; Thomas (prévu) : aucun accès',
  g_ecrire(:'K', :'kb', 'Désolé') = 'OK' and g_ecrire(:'E', :'kb', 'Pas grave') = 'OK'
  and compter_en_tant_que(:'T', format('select count(*)::int from pactes where id = %L', :'pb')) = 0);
select verifier('B', 'D-024 : aucun numéro pour Kevin (sollicité, non sélectionné)',
  compter_en_tant_que(:'K', format('select (telephone_titulaire_accessible(%L) is null)::int', :'kb')) = 1);
select verifier('B', 'David ne lit aucune fiche ni aucun événement du côté d''Eliot',
  compter_en_tant_que(:'D', format('select count(*)::int from remplacants where pacte_id = %L and cote = %L', :'pb', 'initiateur')) = 0
  and compter_en_tant_que(:'D', format('select count(*)::int from evenements_fil where remplacant_id = %L', :'kb')) = 0);
select g_n0() as n1 \gset
select verifier('B', 'échéance relancée : rien (aucun doublon)',
  appliquer_echeances_h3() >= 0 and (select count(*) from notifications_log where id > :n1) = 0
  and (select count(*) from chats_apres_swend where pacte_id = :'pb') = 1);
select verifier('B', 'Swend annulé : plus aucune action (swend_inactif)',
  g_rpc(:'K', 'repondre_demande_remplacement', :'kb', 'true') like '%swend_inactif%');

-- ===================================================================
-- C. Après H-3 : Swend maintenu sans imprévu ; nouvel imprévu d'un titulaire
--    → annulation par lui (pas de recherche)
-- ===================================================================
select g_swend(now() + interval '1 day') as pc \gset
select ajouter_fiche(:'D', :'pc', 'destinataire', 'Thomas', '0600000005') as tc \gset
select ajouter_fiche(:'E', :'pc', 'initiateur', 'Kevin', '0600000003') as kc \gset
select verifier('C', 'après H-3, sans imprévu : l''échéance maintient le Swend', h3_echeance(:'pc', interval '-1 hour') = 0
  and (select statut from pactes where id = :'pc') = 'confirme');
select verifier('C', 'après H-3 : David ne peut plus lancer de recherche (echeance_h3), rien ne bouge',
  h3_rpc(:'pc', interval '-1 hour', :'D', 'envoyer_demande_remplacement', :'tc') like '%echeance_h3%'
  and statut_fiche(:'tc') = 'null' and not h3_declare(:'pc', 'destinataire'));
select g_n0() as n0 \gset
select verifier('C', 'après H-3 : David annule (nouvel imprévu) → annulation immédiate, motif titulaire',
  h3_rpc(:'pc', interval '-1 hour', :'D', 'annuler_swend', :'pc') = 'OK' and ac_annulation(:'pc') = 'annule|titulaire|David|date',
  ac_annulation(:'pc'));
select verifier('C', 'Eliot : « Le Swend est annulé / David ne pourra finalement pas être là. » ; David (auteur), Kevin, Thomas : rien',
  h3_push(:n0, :'E') = 'Le Swend est annulé|David ne pourra finalement pas être là.'
  and h3_push(:n0, :'D') = '' and h3_push(:n0, :'K') = '' and h3_push(:n0, :'T') = '', h3_push(:n0, :'E'));

-- ===================================================================
-- D. Désistement dès H-3 : annulation immédiate, sans réactivation
-- ===================================================================
select g_swend(now() + interval '1 day') as pd \gset
select ajouter_fiche(:'E', :'pd', 'initiateur', 'Kevin', '0600000003') as kd \gset
select ajouter_fiche(:'E', :'pd', 'initiateur', 'Camille', '0600000004') as cd \gset
select ajouter_fiche(:'D', :'pd', 'destinataire', 'Thomas', '0600000005') as td \gset
select en_tant_que(:'E', format('select count(*) from envoyer_demandes_remplacement(array[%L, %L]::uuid[])', :'kd', :'cd')) \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'kd', 'true') \gset
select g_ecrire(:'E', :'kd', 'Merci Kevin') \gset
select verifier('D', 'préparation : Kevin a pris la place (avant H-3), demande de Camille close par cette acceptation',
  statut_fiche(:'kd') = 'acceptee+sel' and statut_fiche(:'cd') = 'cloturee');
select verifier('D', 'Eliot remplacé : l''échéance après H-3 maintient le Swend',
  h3_echeance(:'pd', interval '-30 minutes') = 0 and (select statut from pactes where id = :'pd') = 'confirme');
select g_n0() as n0 \gset
select verifier('D', 'Kevin se désiste à H-3 exactement → Swend annulé (motif echeance_h3, sans auteur)',
  h3_rpc(:'pd', interval '0', :'K', 'se_desister_du_remplacement', :'kd') = 'OK' and ac_annulation(:'pd') = 'annule|echeance_h3|null|date',
  ac_annulation(:'pd'));
select verifier('D', 'aucune réactivation : Camille reste close, aucune demande en attente',
  statut_fiche(:'kd') = 'desistee' and statut_fiche(:'cd') = 'cloturee'
  and not exists (select 1 from remplacants where pacte_id = :'pd' and demande_statut = 'envoyee'));
select verifier('D', 'Eliot : « Le Swend est annulé / Kevin ne peut finalement plus venir. »',
  h3_push(:n0, :'E') = 'Le Swend est annulé|Kevin ne peut finalement plus venir.', h3_push(:n0, :'E'));
select verifier('D', 'David : « Le Swend est annulé / Eliot ne pourra finalement pas être là. » (jamais Kevin)',
  h3_push(:n0, :'D') = 'Le Swend est annulé|Eliot ne pourra finalement pas être là.', h3_push(:n0, :'D'));
select verifier('D', 'Kevin (auteur), Camille (close), Thomas (prévu) : rien ; aucune « Ta réponse est finalement attendue »',
  h3_push(:n0, :'K') = '' and h3_push(:n0, :'C') = '' and h3_push(:n0, :'T') = ''
  and not exists (select 1 from notifications_log where id > :n0 and titre like 'Ta réponse%'));
select verifier('D', 'événement de désistement dans la conversation ; chat d''annulation ; conversation conservée (P1)',
  g_codes(:'kd') like '%desistement%' and ac_chat(:'pd') = 'annulation' and g_ecrire(:'E', :'kd', 'Dommage') = 'OK');
-- Désistement après H-3 (H dans une heure) : même issue.
select g_swend(now() + interval '1 day') as pd2 \gset
select ajouter_fiche(:'E', :'pd2', 'initiateur', 'Kevin', '0600000003') as kd2 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'kd2') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'kd2', 'true') \gset
select verifier('D', 'désistement après H-3 (H dans 1 h) : annulation immédiate',
  h3_rpc(:'pd2', interval '-2 hours', :'K', 'se_desister_du_remplacement', :'kd2') = 'OK'
  and ac_annulation(:'pd2') = 'annule|echeance_h3|null|date');

-- ===================================================================
-- E. Deux côtés en recherche à H-3 : une seule annulation, chacun prévenu
-- ===================================================================
select g_swend(now() + interval '1 day') as pe \gset
select ajouter_fiche(:'E', :'pe', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'D', :'pe', 'destinataire', 'Thomas', '0600000005') as te \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ke') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'te') \gset
select g_n0() as n0 \gset
select verifier('E', 'deux côtés en recherche : Swend annulé une fois', h3_echeance(:'pe', interval '-1 minute') = 1
  and ac_annulation(:'pe') = 'annule|echeance_h3|null|date');
select verifier('E', 'Eliot et David : « Personne n’a pu prendre ta place à temps. » (une push chacun)',
  h3_push(:n0, :'E') = 'Le Swend est annulé|Personne n’a pu prendre ta place à temps.'
  and h3_push(:n0, :'D') = 'Le Swend est annulé|Personne n’a pu prendre ta place à temps.');
select verifier('E', 'Kevin et Thomas (en attente) : « Tu n’as plus besoin de répondre. »',
  h3_push(:n0, :'K') = 'Le Swend est annulé|Tu n’as plus besoin de répondre.'
  and h3_push(:n0, :'T') = 'Le Swend est annulé|Tu n’as plus besoin de répondre.');

-- ===================================================================
-- F. Un côté en recherche, l'autre remplacé : annulation, remplaçant prévenu
-- ===================================================================
select g_swend(now() + interval '1 day') as pf \gset
select ajouter_fiche(:'E', :'pf', 'initiateur', 'Kevin', '0600000003') as kf \gset
select ajouter_fiche(:'D', :'pf', 'destinataire', 'Thomas', '0600000005') as tf \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'tf') \gset
select g_rpc(:'T', 'repondre_demande_remplacement', :'tf', 'true') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'kf') \gset
select g_n0() as n0 \gset
select verifier('F', 'Eliot cherche, David remplacé par Thomas : annulé à H-3', h3_echeance(:'pf', interval '0') = 1);
select verifier('F', 'Thomas : « Tu n’auras finalement pas besoin de prendre la place de David. » ; David : « Eliot ne pourra finalement pas être là. »',
  h3_push(:n0, :'T') = 'Le Swend est annulé|Tu n’auras finalement pas besoin de prendre la place de David.'
  and h3_push(:n0, :'D') = 'Le Swend est annulé|Eliot ne pourra finalement pas être là.'
  and h3_push(:n0, :'E') = 'Le Swend est annulé|Personne n’a pu prendre ta place à temps.'
  and h3_push(:n0, :'K') = 'Le Swend est annulé|Tu n’as plus besoin de répondre.', h3_push(:n0, :'T'));
select verifier('F', 'aucune fuite : ni Kevin dans les push de David et Thomas, ni Thomas dans celles d''Eliot et Kevin',
  h3_push(:n0, :'D') || h3_push(:n0, :'T') not like '%Kevin%'
  and h3_push(:n0, :'E') || h3_push(:n0, :'K') not like '%Thomas%');

-- ===================================================================
-- G. Rappels : l'échéance passe avant le rappel du Jour J
-- ===================================================================
select g_swend('2037-11-16 18:00+00') as pg \gset
select ajouter_fiche(:'E', :'pg', 'initiateur', 'Kevin', '0600000003') as kg \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'kg') \gset
select g_swend('2037-11-17 18:00+00') as pg2 \gset
select g_n0() as n0 \gset
select envoyer_rappels_dus(echeance_rappel('2037-11-16 18:00+00', 'j0')) \gset
select verifier('G', 'Swend en recherche à H-3 : annulé par le moteur des rappels, aucun rappel du Jour J',
  ac_annulation(:'pg') like 'annule|echeance_h3|%'
  and not exists (select 1 from notifications_log where id > :n0 and data->>'type' = 'rappel' and data->>'pacte_id' = :'pg'));
select envoyer_rappels_dus(echeance_rappel('2037-11-17 18:00+00', 'j0')) \gset
select verifier('G', 'Swend maintenu : rappels du Jour J habituels (2)',
  (select statut from pactes where id = :'pg2') = 'confirme'
  and (select count(*) from notifications_log where id > :n0 and data->>'type' = 'rappel' and data->>'pacte_id' = :'pg2') = 2);

-- ===================================================================
-- H. Jobs en échec entre H-3 et H, reprise après H : le premier traitement
--    réussi annule (rattrapage), quel que soit le job qui reprend ; jamais
--    de gel ni de chat après le Swend, aucune push en double ; les Swends
--    maintenus valablement sont figés comme avant.
--    Instants explicites (décembre 2037) : aucun moteur n'est appelé entre
--    les actions (avant H-3) et la reprise, qui simule l'interruption.
-- ===================================================================
-- Push liées à un Swend (titulaires et personnes de confiance) depuis n0,
-- marquées E (Eliot), D (David), K (Kevin), C (Camille).
create or replace function h3_push_swend(p_n0 bigint, p uuid) returns text language sql as $$
  select coalesce(string_agg(case n.profile_id when '00000000-0000-0000-0000-00000000000e' then 'E'
      when '00000000-0000-0000-0000-00000000000d' then 'D' when '00000000-0000-0000-0000-00000000000a' then 'K'
      when '00000000-0000-0000-0000-00000000000c' then 'C' else '?' end || ':' || n.titre || '|' || n.corps, ' ## ' order by n.id), '')
  from notifications_log n
  where n.id > p_n0 and (n.data->>'pacte_id' = p::text
     or n.data->>'remplacant_id' in (select id::text from remplacants where pacte_id = p))
$$;
-- Swend à p_date : Eliot cherche (Kevin en attente, Camille a refusé), avant
-- H-3 ; ensuite plus aucun traitement jusqu'à la reprise.
create or replace function h3_interrompu(p_date timestamptz) returns uuid language plpgsql as $$
declare v uuid; k uuid; c uuid;
begin
  v := g_swend(p_date);
  k := ajouter_fiche('00000000-0000-0000-0000-00000000000e', v, 'initiateur', 'Kevin', '0600000003');
  c := ajouter_fiche('00000000-0000-0000-0000-00000000000e', v, 'initiateur', 'Camille', '0600000004');
  perform g_rpc('00000000-0000-0000-0000-00000000000e', 'envoyer_demande_remplacement', k);
  perform g_rpc('00000000-0000-0000-0000-00000000000e', 'envoyer_demande_remplacement', c);
  perform g_rpc('00000000-0000-0000-0000-00000000000c', 'repondre_demande_remplacement', c, 'false');
  return v;
end $$;
create or replace function h3_fiche(p uuid, p_prenom text) returns uuid language sql as $$
  select id from remplacants where pacte_id = p and prenom = p_prenom
$$;
-- Les trois push d'une annulation à l'échéance quand Eliot cherchait.
\set PUSH_ANNULATION 'E:Le Swend est annulé|Personne n’a pu prendre ta place à temps. ## D:Le Swend est annulé|Eliot ne pourra finalement pas être là. ## K:Le Swend est annulé|Tu n’as plus besoin de répondre.'

-- H1. Reprise par le gel à H (job swend-gel-a-h), 10 minutes après H.
select h3_interrompu('2037-12-01 19:00+00') as ph1 \gset
select h3_fiche(:'ph1', 'Kevin') as kh1 \gset
select h3_fiche(:'ph1', 'Camille') as ch1 \gset
select verifier('H', 'interruption : à H + 10 min, aucun traitement, le Swend est encore confirmé (Kevin en attente)',
  (select statut from pactes where id = :'ph1') = 'confirme' and statut_fiche(:'kh1') = 'envoyee');
select g_n0() as n0 \gset
select figer_swends_passes('2037-12-01 19:10+00') \gset
select verifier('H', 'reprise par le gel : Swend annulé (echeance_h3), pas figé',
  ac_annulation(:'ph1') = 'annule|echeance_h3|null|date' and g_fige(:'ph1') = 'non', ac_annulation(:'ph1') || ' ' || g_fige(:'ph1'));
select verifier('H', 'reprise par le gel : demande de Kevin close, refus de Camille inchangé',
  statut_fiche(:'kh1') = 'cloturee' and statut_fiche(:'ch1') = 'refusee');
select verifier('H', 'reprise par le gel : push de l''annulation, une par personne, jamais « La demande n’est plus d’actualité »',
  h3_push_swend(:n0, :'ph1') = :'PUSH_ANNULATION', h3_push_swend(:n0, :'ph1'));
select verifier('H', 'reprise par le gel : chat d''annulation, aucun événement de fin du Swend',
  ac_chat(:'ph1') = 'annulation' and g_codes(:'kh1') not like '%swend_commence%' and g_codes(:'ch1') not like '%swend_commence%',
  ac_chat(:'ph1') || ' ' || g_codes(:'kh1'));
select verifier('H', 'reprise par le gel : conversation avec Kevin conservée et écrivable (D-027, P1)',
  g_ecrire(:'E', :'kh1', 'Dommage') = 'OK' and g_ecrire(:'K', :'kh1', 'Désolé') = 'OK');
select g_n0() as n1 \gset
select ouvrir_chats_apres_swend(ouverture_chat_apres_swend('2037-12-01 19:00+00') + interval '1 minute') \gset
select appliquer_echeances_h3('2037-12-01 22:05+00') \gset
select figer_swends_passes('2037-12-01 22:05+00') \gset
select envoyer_rappels_dus('2037-12-01 22:05+00') \gset
select verifier('H', 'traitements suivants (chat après le Swend, échéance, gel, rappels) : rien de plus, aucun doublon',
  h3_push_swend(:n1, :'ph1') = '' and ac_chat(:'ph1') = 'annulation' and g_fige(:'ph1') = 'non'
  and ac_annulation(:'ph1') = 'annule|echeance_h3|null|date'
  and (select count(*) from chats_apres_swend where pacte_id = :'ph1') = 1, h3_push_swend(:n1, :'ph1'));

-- H2. Reprise par le job de l'échéance, 2 heures après H.
select h3_interrompu('2037-12-02 19:00+00') as ph2 \gset
select g_n0() as n0 \gset
select verifier('H', 'reprise par le job de l''échéance (H + 2 h) : Swend annulé',
  appliquer_echeances_h3('2037-12-02 21:00+00') >= 1 and ac_annulation(:'ph2') = 'annule|echeance_h3|null|date');
select figer_swends_passes('2037-12-02 21:01+00') \gset
select ouvrir_chats_apres_swend(ouverture_chat_apres_swend('2037-12-02 19:00+00') + interval '1 minute') \gset
select verifier('H', 'puis gel et chat après le Swend : jamais figé, seul le chat d''annulation, push une fois chacun',
  g_fige(:'ph2') = 'non' and ac_chat(:'ph2') = 'annulation' and h3_push_swend(:n0, :'ph2') = :'PUSH_ANNULATION',
  h3_push_swend(:n0, :'ph2'));

-- H3. Reprise par le moteur des rappels, 30 minutes après H.
select h3_interrompu('2037-12-03 19:00+00') as ph3 \gset
select g_n0() as n0 \gset
select envoyer_rappels_dus('2037-12-03 19:30+00') \gset
select verifier('H', 'reprise par le moteur des rappels : Swend annulé, aucun rappel, push une fois chacun',
  ac_annulation(:'ph3') = 'annule|echeance_h3|null|date' and h3_push_swend(:n0, :'ph3') = :'PUSH_ANNULATION',
  h3_push_swend(:n0, :'ph3'));

-- H4. Le job du chat après le Swend passe le premier, après l'heure
-- d'ouverture du chat : il ne fait rien (Swend non figé) ; le gel annule.
select h3_interrompu('2037-12-04 19:00+00') as ph4 \gset
select g_n0() as n0 \gset
select ouvrir_chats_apres_swend(ouverture_chat_apres_swend('2037-12-04 19:00+00') + interval '5 minutes') \gset
select verifier('H', 'chat après le Swend en premier (H + 3 h 05) : aucun chat ouvert, Swend toujours confirmé',
  ac_chat(:'ph4') = 'aucun' and (select statut from pactes where id = :'ph4') = 'confirme' and h3_push_swend(:n0, :'ph4') = '');
select figer_swends_passes('2037-12-04 22:06+00') \gset
select ouvrir_chats_apres_swend('2037-12-04 22:07+00') \gset
select verifier('H', 'puis gel : annulé, chat d''annulation seulement, jamais « Alors, ce Swend ? »',
  ac_annulation(:'ph4') = 'annule|echeance_h3|null|date' and ac_chat(:'ph4') = 'annulation'
  and h3_push_swend(:n0, :'ph4') = :'PUSH_ANNULATION', h3_push_swend(:n0, :'ph4'));

-- H5. Swends maintenus valablement, même interruption puis reprise : rien
-- ne change pour eux (gel, événement de fin, chat après le Swend).
select g_swend('2037-12-06 19:00+00') as pm1 \gset
select ajouter_fiche(:'E', :'pm1', 'initiateur', 'Kevin', '0600000003') as km1 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'km1') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'km1', 'true') \gset
select g_swend('2037-12-06 19:00+00') as pm2 \gset
select ajouter_fiche(:'E', :'pm2', 'initiateur', 'Kevin', '0600000003') as km2 \gset
select g_ecrire(:'E', :'km2', 'Au cas où') \gset
select g_swend('2037-12-06 19:00+00') as pm3 \gset
select ajouter_fiche(:'E', :'pm3', 'initiateur', 'Kevin', '0600000003') as km3 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'km3') \gset
select g_rpc(:'E', 'je_peux_finalement_venir', :'pm3') \gset
select g_n0() as n0 \gset
select figer_swends_passes('2037-12-06 19:10+00') \gset
select verifier('H', 'maintenus (Kevin a accepté ; aucune demande ; « Je peux finalement venir ») : figés, confirmés',
  g_fige(:'pm1') = 'traite' and g_fige(:'pm2') = 'traite' and g_fige(:'pm3') = 'traite'
  and (select count(*) from pactes where id in (:'pm1', :'pm2', :'pm3') and statut = 'confirme' and annule_motif is null) = 3);
select verifier('H', 'maintenus : événement de fin comme avant, aucune push d''annulation',
  g_codes(:'km1') like '%swend_commence' and g_codes(:'km2') like '%swend_commence'
  and h3_push_swend(:n0, :'pm1') || h3_push_swend(:n0, :'pm2') || h3_push_swend(:n0, :'pm3') not like '%annulé%');
select ouvrir_chats_apres_swend(ouverture_chat_apres_swend('2037-12-06 19:00+00') + interval '1 minute') \gset
select verifier('H', 'maintenus : chat après le Swend ouvert (« Alors, ce Swend ? »), Kevin participant là où il remplace',
  ac_chat(:'pm1') = 'apres_swend' and ac_chat(:'pm2') = 'apres_swend' and ac_chat(:'pm3') = 'apres_swend'
  and h3_push_swend(:n0, :'pm1') like '%K:Alors, ce Swend ?%', h3_push_swend(:n0, :'pm1'));

-- H6. Garde-fou : Swend déjà figé par un gel antérieur à la règle (cas exclu
-- par la précondition du paquet) : l'échéance ne revient pas dessus.
select h3_interrompu('2037-12-07 19:00+00') as ph6 \gset
insert into swends_figes (pacte_id, date_retenue, rattrapage) values (:'ph6', '2037-12-07 19:00+00', true);
select appliquer_echeances_h3('2037-12-07 19:10+00') \gset
select verifier('H', 'Swend déjà figé avant la règle : laissé tel quel (ni annulation ni push)',
  (select statut from pactes where id = :'ph6') = 'confirme');

-- H7. Interruption longue : reprise 3 jours après H par le gel.
select h3_interrompu('2037-12-10 19:00+00') as ph7 \gset
select g_n0() as n0 \gset
select figer_swends_passes('2037-12-13 19:00+00') \gset
select verifier('H', 'reprise 3 jours après H : annulé quand même, chat d''annulation, push une fois chacun',
  ac_annulation(:'ph7') = 'annule|echeance_h3|null|date' and g_fige(:'ph7') = 'non' and ac_chat(:'ph7') = 'annulation'
  and h3_push_swend(:n0, :'ph7') = :'PUSH_ANNULATION', h3_push_swend(:n0, :'ph7'));

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
