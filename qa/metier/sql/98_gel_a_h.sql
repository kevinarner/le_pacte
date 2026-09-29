-- Gel à l'heure du Swend (D-023a). Utilise les outils de 10_imprevu.sql
-- (verifier, en_tant_que, compter_en_tant_que, statut_fiche, ajouter_fiche).
-- Les Swends sont datés par rapport à l'horloge réelle (« juste avant » :
-- dans une heure ; « juste après » : il y a une seconde) : chaque instruction
-- psql est une transaction, now() avance d'une instruction à l'autre.
-- Le moteur est appelé avec l'instant réel, sauf pour le changement d'heure
-- (instant contrôlé).
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
-- Swend scellé Eliot (initiateur) / David (destinataire) à la date donnée.
create or replace function g_swend(p_date timestamptz) returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, type, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
                      destinataire_id, destinataire_nom, destinataire_telephone)
  values ('confirme', 'diner', p_date, '00000000-0000-0000-0000-0000000000aa',
          '00000000-0000-0000-0000-00000000000e', 'Eliot E',
          '00000000-0000-0000-0000-00000000000d', 'David D', '06 00 00 00 02')
  returning id into v;
  return v;
end $$;
-- Change l'heure d'un Swend (en postgres : l'app ne le peut plus).
create or replace function g_dater(p uuid, p_date timestamptz) returns void language sql as $$
  update pactes set date_retenue = p_date where id = p
$$;
create or replace function g_rpc(p_user uuid, p_fonction text, p_arg uuid, p_arg2 text default null) returns text language sql as $$
  select en_tant_que(p_user, case when p_arg2 is null
    then format('select %s(%L)', p_fonction, p_arg)
    else format('select %s(%L, %s)', p_fonction, p_arg, p_arg2) end)
$$;
create or replace function g_ecrire(p_user uuid, p_fiche uuid, p_texte text) returns text language sql as $$
  select en_tant_que(p_user, format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)',
                                    p_fiche, p_user, p_texte))
$$;
create or replace function g_lire(p_user uuid, p_fiche uuid) returns int language sql as $$
  select compter_en_tant_que(p_user, format('select count(*)::int from messages where remplacant_id = %L', p_fiche))
$$;
create or replace function g_codes(p uuid) returns text language sql as $$
  select coalesce(string_agg(code, ',' order by created_at, id), '') from evenements_fil where remplacant_id = p
$$;
create or replace function g_push(p_n0 bigint, p_profil uuid) returns text language sql as $$
  select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '')
  from notifications_log where id > p_n0 and profile_id = p_profil
$$;
create or replace function g_nb_push(p_n0 bigint) returns int language sql as $$
  select count(*)::int from notifications_log where id > p_n0
$$;
create or replace function g_n0() returns bigint language sql as $$
  select coalesce(max(id), 0) from notifications_log
$$;
create or replace function g_fige(p uuid) returns text language sql as $$
  select coalesce((select case when rattrapage then 'rattrapage' else 'traite' end
                   from swends_figes where pacte_id = p), 'non')
$$;

-- Les Swends passés laissés par les autres fichiers de test sont traités
-- d'abord : la suite ne compte que ses propres Swends.
select figer_swends_passes();

-- ===================================================================
-- A. Juste avant H : toutes les actions restent possibles
-- ===================================================================
select g_swend(now() + interval '1 hour') as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select verifier('A', 'ajouter une personne de confiance avant H', :'k' is not null and :'t' is not null);
select verifier('A', 'demander avant H', g_rpc(:'E', 'envoyer_demande_remplacement', :'k') = 'OK');
select verifier('A', 'annuler une demande avant H', g_rpc(:'E', 'annuler_demande_remplacement', :'k') = 'OK');
select verifier('A', 'refuser avant H',
  g_rpc(:'E', 'envoyer_demande_remplacement', :'k') = 'OK'
  and g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'false') = 'OK' and statut_fiche(:'k') = 'refusee');
select verifier('A', 'accepter avant H',
  g_rpc(:'E', 'envoyer_demande_remplacement', :'c') = 'OK'
  and g_rpc(:'C', 'repondre_demande_remplacement', :'c', 'true') = 'OK' and statut_fiche(:'c') = 'acceptee+sel');
select verifier('A', 'se désister avant H', g_rpc(:'C', 'se_desister_du_remplacement', :'c') = 'OK');
select verifier('A', 'signaler indisponibilité puis disponibilité avant H',
  g_rpc(:'T', 'signaler_indisponibilite', :'t') = 'OK' and g_rpc(:'T', 'signaler_disponibilite', :'t') = 'OK');
select verifier('A', 'ajouter et demander avant H',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)',
    :'p', 'initiateur', 'Zoé', 'Z', '0600000006')) = 'OK');
select verifier('A', 'retirer une personne avant H', g_rpc(:'E', 'retirer_remplacant', :'k') = 'OK');
select verifier('A', 'écrire dans une conversation avant H (titulaire et personne de confiance)',
  g_ecrire(:'E', :'t', 'Tu es là le 13 ?') = 'OK' and g_ecrire(:'T', :'t', 'Oui') = 'OK');
select verifier('A', 'annuler le Swend reste possible avant H (non exécuté ici)', statut_fiche(:'t') = 'null');

-- ===================================================================
-- B. Juste après H : tout est refusé avec swend_passe, rien ne bouge
-- ===================================================================
select g_swend(now() + interval '1 hour') as p2 \gset
select ajouter_fiche(:'E', :'p2', 'initiateur', 'Kevin', '0600000003') as k2 \gset
select ajouter_fiche(:'E', :'p2', 'initiateur', 'Camille', '0600000004') as c2 \gset
select ajouter_fiche(:'E', :'p2', 'initiateur', 'Tom', '0700000010') as v2 \gset
select ajouter_fiche(:'D', :'p2', 'destinataire', 'Thomas', '0600000005') as t2 \gset
select ajouter_fiche(:'D', :'p2', 'destinataire', 'Kevin', '0600000003') as kd2 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k2') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'t2') \gset
select g_rpc(:'T', 'repondre_demande_remplacement', :'t2', 'true') \gset
select g_rpc(:'K', 'signaler_indisponibilite', :'kd2') \gset
select g_ecrire(:'C', :'c2', 'Je peux venir si besoin') \gset
select verifier('B', 'préparation : Kevin sollicité, Thomas a accepté côté David, Kevin indisponible côté David',
  statut_fiche(:'k2') = 'envoyee' and statut_fiche(:'t2') = 'acceptee+sel'
  and (select indisponible_spontanement from remplacants where id = :'kd2'));
select g_dater(:'p2', now() - interval '1 second');
select g_n0() as n0 \gset
select verifier('B', 'demander après H → swend_passe', g_rpc(:'E', 'envoyer_demande_remplacement', :'c2') like '%swend_passe%',
  g_rpc(:'E', 'envoyer_demande_remplacement', :'c2'));
select verifier('B', 'annuler une demande après H → swend_passe', g_rpc(:'E', 'annuler_demande_remplacement', :'k2') like '%swend_passe%');
select verifier('B', 'accepter après H → swend_passe', g_rpc(:'K', 'repondre_demande_remplacement', :'k2', 'true') like '%swend_passe%');
select verifier('B', 'refuser après H → swend_passe', g_rpc(:'K', 'repondre_demande_remplacement', :'k2', 'false') like '%swend_passe%');
select verifier('B', 'se désister après H → swend_passe', g_rpc(:'T', 'se_desister_du_remplacement', :'t2') like '%swend_passe%');
select verifier('B', 'ajouter et demander après H → swend_passe',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)',
    :'p2', 'initiateur', 'Zoé', 'Z', '0600000006')) like '%swend_passe%');
select verifier('B', 'signaler une indisponibilité après H → swend_passe', g_rpc(:'C', 'signaler_indisponibilite', :'c2') like '%swend_passe%');
select verifier('B', 'signaler une disponibilité après H → swend_passe', g_rpc(:'K', 'signaler_disponibilite', :'kd2') like '%swend_passe%');
select verifier('B', 'ajouter une personne de confiance après H → swend_passe',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p2', 'initiateur', 'Zoé', 'Z', '0600000006', '')) like '%swend_passe%');
select verifier('B', 'retirer une personne après H → swend_passe', g_rpc(:'E', 'retirer_remplacant', :'c2') like '%swend_passe%');
select verifier('B', 'annuler le Swend après H → swend_passe (D-022 conservé)', g_rpc(:'E', 'annuler_swend', :'p2') like '%swend_passe%');
select verifier('B', 'rien n''a bougé (fiches, statut, aucune push)',
  statut_fiche(:'k2') = 'envoyee' and statut_fiche(:'t2') = 'acceptee+sel' and statut_fiche(:'c2') = 'null'
  and (select retire_le is null from remplacants where id = :'c2')
  and (select count(*) from remplacants where pacte_id = :'p2') = 5
  and (select statut from pactes where id = :'p2') = 'confirme' and g_nb_push(:n0) = 0);
select verifier('B', 'conversation : plus d''écriture après H (titulaire et personne de confiance)',
  g_ecrire(:'E', :'c2', 'Merci') like '%row-level security%' and g_ecrire(:'C', :'c2', 'Avec plaisir') like '%row-level security%');
select verifier('B', 'conversation : l''historique reste lisible des deux côtés',
  g_lire(:'C', :'c2') = 1 and g_lire(:'E', :'c2') = 1);
select verifier('B', 'plus de modification ni suppression d''un message après H',
  en_tant_que(:'C', format('update messages set contenu = %L where remplacant_id = %L', 'x', :'c2')) = 'OK'
  and en_tant_que(:'C', format('delete from messages where remplacant_id = %L', :'c2')) = 'OK'
  and (select string_agg(contenu, '') from messages where remplacant_id = :'c2') = 'Je peux venir si besoin');

-- ===================================================================
-- C. Moteur à H : clôture, push validée, événement de fin, idempotence
-- ===================================================================
select g_n0() as n0 \gset
select verifier('C', 'moteur avant l''heure : Swend non traité', g_fige(:'p2') = 'non');
select figer_swends_passes() as nb \gset
select verifier('C', 'le moteur traite le Swend passé (et lui seul)', :nb = 1 and g_fige(:'p2') = 'traite', :'nb');
select verifier('C', 'demande en attente clôturée', statut_fiche(:'k2') = 'cloturee');
select verifier('C', 'Kevin : une seule push, texte validé',
  g_push(:n0, :'K') = 'La demande n’est plus d’actualité|L’heure du Swend est passée.', g_push(:n0, :'K'));
select verifier('C', 'push de Kevin : ouvre sa conversation',
  (select data->>'type' = 'chat' and data->>'remplacant_id' = :'k2' and data->>'nom_interlocuteur' = 'Eliot E'
   from notifications_log where id > :n0 and profile_id = :'K'));
select verifier('C', 'aucune autre push (titulaires, remplaçant accepté, « quelqu''un a pu prendre la place »)',
  g_nb_push(:n0) = 1 and not exists (select 1 from notifications_log where id > :n0 and corps like '%a pu prendre la place%'));
select verifier('C', 'événements : clôture puis fin (demande en attente)',
  g_codes(:'k2') = 'demande_envoyee,demande_cloturee,swend_commence', g_codes(:'k2'));
select verifier('C', 'événement de fin dans une conversation avec seulement un message', g_codes(:'c2') = 'swend_commence', g_codes(:'c2'));
select verifier('C', 'événement de fin après l''acceptation (remplaçant sélectionné, inchangé)',
  g_codes(:'t2') = 'demande_envoyee,demande_acceptee,swend_commence' and statut_fiche(:'t2') = 'acceptee+sel', g_codes(:'t2'));
select verifier('C', 'événement de fin après une indisponibilité', g_codes(:'kd2') = 'indisponibilite_signalee,swend_commence', g_codes(:'kd2'));
select verifier('C', 'conversation vierge : aucun événement créé', g_codes(:'v2') = '', g_codes(:'v2'));
select verifier('C', 'l''événement de fin est le dernier de la conversation',
  (select code from evenements_fil where remplacant_id = :'k2' order by created_at desc, id desc limit 1) = 'swend_commence');
select verifier('C', 'Kevin lit l''événement de fin de sa conversation (RLS)',
  compter_en_tant_que(:'K', format('select count(*)::int from evenements_fil where remplacant_id = %L and code = %L', :'k2', 'swend_commence')) = 1);
select verifier('C', 'David ne lit aucun événement côté Eliot',
  compter_en_tant_que(:'D', format('select count(*)::int from evenements_fil where remplacant_id = %L', :'k2')) = 0);
select verifier('C', 'répondre après la clôture : toujours swend_passe', g_rpc(:'K', 'repondre_demande_remplacement', :'k2', 'true') like '%swend_passe%');
select count(*) as nev from evenements_fil \gset
select g_n0() as n1 \gset
select figer_swends_passes() as nb2 \gset
select verifier('C', 'moteur appelé une deuxième fois : rien (aucun doublon)',
  :nb2 = 0 and (select count(*) from evenements_fil) = :nev and g_nb_push(:n1) = 0);
select verifier('C', 'le statut reste confirme (aucun indicateur modifié)', (select statut from pactes where id = :'p2') = 'confirme');

-- ===================================================================
-- D. Même personne sollicitée des deux côtés : une seule push
-- ===================================================================
select g_swend(now() + interval '1 hour') as p3 \gset
select ajouter_fiche(:'E', :'p3', 'initiateur', 'Kevin', '0600000003') as ke3 \gset
select ajouter_fiche(:'D', :'p3', 'destinataire', 'Kevin', '0600000003') as kd3 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ke3') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'kd3') \gset
select g_dater(:'p3', now() - interval '1 second');
select g_n0() as n0 \gset
select figer_swends_passes() \gset
select verifier('D', 'les deux demandes sont clôturées', statut_fiche(:'ke3') = 'cloturee' and statut_fiche(:'kd3') = 'cloturee');
select verifier('D', 'Kevin : une seule push', g_push(:n0, :'K') = 'La demande n’est plus d’actualité|L’heure du Swend est passée.'
  and g_nb_push(:n0) = 1, g_push(:n0, :'K'));
select verifier('D', 'événement de fin dans les deux conversations',
  g_codes(:'ke3') like '%,swend_commence' and g_codes(:'kd3') like '%,swend_commence');

-- ===================================================================
-- E. Moteur en retard de plus de 12 heures : état corrigé, sans push
-- ===================================================================
select g_swend(now() + interval '1 hour') as p4 \gset
select ajouter_fiche(:'E', :'p4', 'initiateur', 'Kevin', '0600000003') as k4 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k4') \gset
select g_dater(:'p4', now() - interval '13 hours');
select g_n0() as n0 \gset
select figer_swends_passes() \gset
select verifier('E', 'demande clôturée, événements présents, aucune push tardive',
  statut_fiche(:'k4') = 'cloturee' and g_codes(:'k4') like '%,swend_commence' and g_nb_push(:n0) = 0);

-- ===================================================================
-- F. Changement d'heure (Europe/Paris) : H est un instant absolu
-- ===================================================================
select g_swend(timestamp '2037-10-25 20:00' at time zone 'Europe/Paris') as p5 \gset
select g_swend(timestamp '2037-03-29 20:00' at time zone 'Europe/Paris') as p6 \gset
select verifier('F', 'dates : 19h00 UTC (heure d''hiver) et 18h00 UTC (heure d''été)',
  (select date_retenue from pactes where id = :'p5') = '2037-10-25 19:00+00'
  and (select date_retenue from pactes where id = :'p6') = '2037-03-29 18:00+00');
select figer_swends_passes('2037-03-29 17:59:59+00') \gset
select verifier('F', 'été : rien une seconde avant 20h00 Paris', g_fige(:'p6') = 'non');
select figer_swends_passes('2037-03-29 18:00+00') \gset
select verifier('F', 'été : traité à 20h00 Paris exactement', g_fige(:'p6') = 'traite');
select figer_swends_passes('2037-10-25 18:30+00') \gset
select verifier('F', 'hiver : rien à 19h30 Paris (pas de décalage d''une heure)', g_fige(:'p5') = 'non');
select figer_swends_passes('2037-10-25 19:00+00') \gset
select verifier('F', 'hiver : traité à 20h00 Paris exactement', g_fige(:'p5') = 'traite');

-- ===================================================================
-- G. Swend annulé : conversations en lecture seule immédiatement
-- ===================================================================
select g_swend(now() + interval '1 day') as p7 \gset
select ajouter_fiche(:'E', :'p7', 'initiateur', 'Kevin', '0600000003') as k7 \gset
select g_ecrire(:'K', :'k7', 'Bon appétit !') \gset
select verifier('G', 'avant l''annulation : on écrit', g_ecrire(:'E', :'k7', 'Merci') = 'OK');
select verifier('G', 'Eliot annule le Swend', g_rpc(:'E', 'annuler_swend', :'p7') = 'OK');
select verifier('G', 'annulé : plus d''écriture, même avant l''heure',
  g_ecrire(:'E', :'k7', 'Dommage') like '%row-level security%' and g_ecrire(:'K', :'k7', 'Pas grave') like '%row-level security%');
select verifier('G', 'annulé : historique lisible', g_lire(:'K', :'k7') = 2 and g_lire(:'E', :'k7') = 2);
select g_dater(:'p7', now() - interval '1 second');
select figer_swends_passes() \gset
select verifier('G', 'annulé puis passé : pas traité par le moteur, aucun événement de fin',
  g_fige(:'p7') = 'non' and g_codes(:'k7') not like '%swend_commence%');
-- Double remplacement.
select g_swend(now() + interval '1 day') as p8 \gset
select ajouter_fiche(:'E', :'p8', 'initiateur', 'Kevin', '0600000003') as k8 \gset
select ajouter_fiche(:'D', :'p8', 'destinataire', 'Camille', '0600000004') as c8 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k8') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'c8') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k8', 'true') \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'c8', 'true') \gset
select verifier('G', 'double remplacement : Swend annulé et conversations en lecture seule',
  (select statut from pactes where id = :'p8') = 'annuleDoubleAbsence'
  and g_ecrire(:'K', :'k8', 'Oh') like '%row-level security%' and g_ecrire(:'D', :'c8', 'Oh') like '%row-level security%');

-- ===================================================================
-- H. Retirer une personne : rien n'est détruit
-- ===================================================================
select g_swend(now() + interval '1 day') as p9 \gset
select ajouter_fiche(:'E', :'p9', 'initiateur', 'Thomas', '0600000005') as t9 \gset
select ajouter_fiche(:'E', :'p9', 'initiateur', 'Kevin', '0600000003') as k9 \gset
select g_ecrire(:'T', :'t9', 'Je serai en vacances') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'t9') \gset
select g_rpc(:'T', 'repondre_demande_remplacement', :'t9', 'false') \gset
select verifier('H', 'retirer Thomas (a refusé)', g_rpc(:'E', 'retirer_remplacant', :'t9') = 'OK');
select verifier('H', 'fiche archivée, message et événements conservés',
  (select retire_le is not null from remplacants where id = :'t9')
  and (select count(*) from messages where remplacant_id = :'t9') = 1
  and g_codes(:'t9') = 'demande_envoyee,demande_refusee');
select verifier('H', 'retirer deux fois : sans effet, sans erreur', g_rpc(:'E', 'retirer_remplacant', :'t9') = 'OK');
select verifier('H', 'Thomas n''a plus accès au Swend ni à sa fiche',
  compter_en_tant_que(:'T', format('select count(*)::int from pactes where id = %L', :'p9')) = 0
  and compter_en_tant_que(:'T', format('select count(*)::int from remplacants where id = %L', :'t9')) = 0
  and g_lire(:'T', :'t9') = 0);
select verifier('H', 'Eliot garde l''historique en base (lisible) mais n''y écrit plus',
  g_lire(:'E', :'t9') = 1 and g_ecrire(:'E', :'t9', 'Bonnes vacances') like '%row-level security%');
select verifier('H', 'une fiche retirée ne peut plus être sollicitée',
  g_rpc(:'E', 'envoyer_demande_remplacement', :'t9') like '%demande_non_active%');
select ajouter_fiche(:'E', :'p9', 'initiateur', 'Thomas', '0600000005') \gset
select verifier('H', 'Thomas peut être ajouté à nouveau (nouvelle fiche, nouvelle conversation)',
  (select string_agg(statut_fiche(id), ',') from remplacants
       where pacte_id = :'p9' and prenom = 'Thomas' and retire_le is null) = 'null');
select verifier('H', 'retrait d''un refus : Eliot ne « cherche » plus (rappels)',
  etat_cote_titulaire(:'p9', 'initiateur') = 'normal');
select g_dater(:'p9', now() - interval '1 second');
select figer_swends_passes() \gset
select verifier('H', 'fiche retirée : aucun événement de fin', g_codes(:'t9') = 'demande_envoyee,demande_refusee');

-- ===================================================================
-- I. Ancien rappel cliqué après H : jamais « Un imprévu ? »
-- ===================================================================
select g_swend(now() + interval '1 hour') as p10 \gset
select ajouter_fiche(:'E', :'p10', 'initiateur', 'Kevin', '0600000003') as k10 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k10') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k10', 'false') \gset
select en_tant_que(:'E', format('select set_config(%L, destination_rappel(%L), false)', 'qa.dest', :'p10')) \gset
select verifier('I', 'avant H : Eliot qui cherche → Un imprévu ?', current_setting('qa.dest') = 'imprevu', current_setting('qa.dest'));
select g_dater(:'p10', now() - interval '1 second');
select en_tant_que(:'E', format('select set_config(%L, destination_rappel(%L), false)', 'qa.dest', :'p10')) \gset
select verifier('I', 'après H : fiche du Swend', current_setting('qa.dest') = 'fiche', current_setting('qa.dest'));

-- ===================================================================
-- J. Jamais de scellement dans le passé ; date d'un Swend scellé figée
-- ===================================================================
insert into pactes (id, statut, type, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
                    destinataire_nom, destinataire_telephone)
values ('00000000-0000-4000-9800-000000000001', 'enAttenteReponse', 'diner', array[now() - interval '1 minute'],
        now() - interval '1 minute', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', 'David D', '06 00 00 00 02'),
       ('00000000-0000-4000-9800-000000000002', 'enAttenteReponse', 'diner', array[now() + interval '1 day'],
        now() + interval '1 day', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', 'David D', '06 00 00 00 02');
select verifier('J', 'David ne peut pas sceller un Swend dont l''heure est passée',
  en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'confirme', '00000000-0000-4000-9800-000000000001')) like '%swend_passe%'
  and (select statut || coalesce(scelle_le::text, '-') from pactes where id = '00000000-0000-4000-9800-000000000001') = 'enAttenteReponse-');
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'confirme', '00000000-0000-4000-9800-000000000002')) as r \gset
select verifier('J', 'sceller un Swend à venir reste possible',
  :'r' = 'OK' and (select scelle_le is not null from pactes where id = '00000000-0000-4000-9800-000000000002'), :'r');
select verifier('J', 'créer directement un Swend scellé déjà passé : refusé',
  en_tant_que(:'E', format('insert into pactes (statut, type, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone) values (%L, %L, array[%L::timestamptz], %L, %L, %L, %L, %L, %L)',
    'confirme', 'diner', now() - interval '1 hour', now() - interval '1 hour', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', 'David D', '06 00 00 00 02')) like '%swend_passe%');
select verifier('J', 'la date d''un Swend scellé n''est plus modifiable par l''app',
  en_tant_que(:'E', format('update pactes set date_retenue = %L where id = %L', now() + interval '2 days', '00000000-0000-4000-9800-000000000002')) like '%modification_interdite%');

-- ===================================================================
-- K. Rattrapage : l'historique déjà passé ne génère rien
-- ===================================================================
select g_swend(now() - interval '2 days') as p11 \gset
insert into remplacants (pacte_id, cote, prenom, nom, telephone, email)
values (:'p11', 'initiateur', 'Kevin', 'X', '0600000003', '') returning id as k11 \gset
update remplacants set demande_statut = 'envoyee' where id = :'k11';
select count(*) as nev11 from evenements_fil where remplacant_id = :'k11' \gset
select verifier('K', 'rattrapage : le Swend déjà passé est marqué traité', rattraper_swends_figes() >= 1 and g_fige(:'p11') = 'rattrapage');
select g_n0() as n0 \gset
select figer_swends_passes() \gset
select verifier('K', 'rattrapage : aucune clôture, aucune push, aucun événement rétroactif',
  statut_fiche(:'k11') = 'envoyee' and g_nb_push(:n0) = 0
  and (select count(*) from evenements_fil where remplacant_id = :'k11') = :nev11);
select verifier('K', 'rattrapage : même un appel de l''app est refusé (swend_passe)',
  g_rpc(:'K', 'repondre_demande_remplacement', :'k11', 'true') like '%swend_passe%');

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
