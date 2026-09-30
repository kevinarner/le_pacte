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
select verifier('B', 'conversation : Eliot garde l''historique, Camille (seulement prévue) n''y a plus accès',
  g_lire(:'E', :'c2') = 1 and g_lire(:'C', :'c2') = 0);
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
select verifier('C', 'push de Kevin : fiche du Swend (il n''y a plus accès : l''app reste sur l''accueil)',
  (select data = jsonb_build_object('type', 'pacte', 'pacte_id', :'p2')
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
select verifier('C', 'Eliot lit l''événement de fin ; Kevin (sollicité, sans place) n''a plus accès',
  compter_en_tant_que(:'E', format('select count(*)::int from evenements_fil where remplacant_id = %L and code = %L', :'k2', 'swend_commence')) = 1
  and compter_en_tant_que(:'K', format('select count(*)::int from evenements_fil where remplacant_id = %L', :'k2')) = 0);
select verifier('C', 'Thomas (remplaçant sélectionné) lit l''événement de fin de sa conversation',
  compter_en_tant_que(:'T', format('select count(*)::int from evenements_fil where remplacant_id = %L and code = %L', :'t2', 'swend_commence')) = 1);
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
select verifier('G', 'annulé : Eliot relit l''historique ; Kevin (seulement prévu) n''y a plus accès',
  g_lire(:'E', :'k7') = 2 and g_lire(:'K', :'k7') = 0);
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

-- ===================================================================
-- L. Swend annulé : les conversations ayant eu une activité restent
--    relisibles (lecture seule) par ceux qui y avaient accès
-- ===================================================================
select g_swend(now() + interval '1 day') as p12 \gset
select ajouter_fiche(:'E', :'p12', 'initiateur', 'Kevin', '0600000003') as k12 \gset
select ajouter_fiche(:'E', :'p12', 'initiateur', 'Camille', '0600000004') as c12 \gset
select ajouter_fiche(:'E', :'p12', 'initiateur', 'Thomas', '0600000005') as t12 \gset
select en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)',
  :'p12', 'initiateur', 'Tom', 'Sans Compte', '0700000011')) \gset
select id as tom12 from remplacants where pacte_id = :'p12' and prenom = 'Tom' \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k12') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k12', 'true') \gset
select g_ecrire(:'E', :'k12', 'Merci Kevin') \gset
select g_ecrire(:'C', :'c12', 'Bon Swend !') \gset
select g_rpc(:'E', 'annuler_swend', :'p12') \gset
select verifier('L', 'Swend annulé', (select statut from pactes where id = :'p12') = 'annule');
-- La requête de l'app (filsAvecActivite) : fiches ayant un message ou un
-- événement, lues sous la RLS d'Eliot.
select verifier('L', 'Eliot : conversations actives relisibles (Kevin, Camille, Tom sans compte), pas le fil vierge de Thomas',
  compter_en_tant_que(:'E', format(
    'select count(distinct remplacant_id)::int from (select remplacant_id from messages where remplacant_id in (%L, %L, %L, %L)
     union all select remplacant_id from evenements_fil where remplacant_id in (%L, %L, %L, %L)) x',
    :'k12', :'c12', :'t12', :'tom12', :'k12', :'c12', :'t12', :'tom12')) = 3);
select verifier('L', 'Eliot relit le message à Kevin et les événements du fil de Tom',
  g_lire(:'E', :'k12') = 1
  and compter_en_tant_que(:'E', format('select count(*)::int from evenements_fil where remplacant_id = %L', :'tom12')) >= 1);
select verifier('L', 'Kevin (remplaçant accepté) relit sa conversation',
  g_lire(:'K', :'k12') = 1
  and compter_en_tant_que(:'K', format('select count(*)::int from evenements_fil where remplacant_id = %L', :'k12')) >= 1);
select verifier('L', 'Camille (seulement prévue) n''a plus accès à sa conversation ni au Swend',
  g_lire(:'C', :'c12') = 0
  and compter_en_tant_que(:'C', format('select count(*)::int from pactes where id = %L', :'p12')) = 0
  and compter_en_tant_que(:'C', format('select count(*)::int from remplacants where id = %L', :'c12')) = 0);
select verifier('L', 'Eliot relit toujours la conversation avec Camille', g_lire(:'E', :'c12') = 1);
select verifier('L', 'personne ne peut plus y écrire',
  g_ecrire(:'E', :'k12', 'x') like '%row-level security%' and g_ecrire(:'K', :'k12', 'x') like '%row-level security%'
  and g_ecrire(:'C', :'c12', 'x') like '%row-level security%');
select verifier('L', 'David ne lit aucune de ces conversations',
  compter_en_tant_que(:'D', format('select count(*)::int from messages where remplacant_id in (%L, %L)', :'k12', :'c12')) = 0
  and compter_en_tant_que(:'D', format('select count(*)::int from evenements_fil where remplacant_id in (%L, %L, %L)', :'k12', :'c12', :'tom12')) = 0);

-- ===================================================================
-- M. Matrice d'accès (RLS, comme l'API) : Swend / fiche / messages /
--    événements, par rôle, avant H, après H et après annulation
-- ===================================================================
\set W '00000000-0000-0000-0000-000000000077'
\set Y '00000000-0000-0000-0000-000000000078'
\set X '00000000-0000-0000-0000-000000000079'
insert into profiles (id, prenom, nom, telephone) values
  (:'W', 'Walter', 'W', '0600000007'), (:'Y', 'Yann', 'Y', '0600000008'),
  (:'X', 'Xavier', 'X', '0600000009') on conflict do nothing;
-- « swend/fiche/messages/événements » lus par p_user (RLS appliquée).
create or replace function g_acces(p_user uuid, p_pacte uuid, p_fiche uuid) returns text language sql as $$
  select compter_en_tant_que(p_user, format('select count(*)::int from pactes where id = %L', p_pacte)) || '/'
      || compter_en_tant_que(p_user, format('select count(*)::int from remplacants where id = %L', p_fiche)) || '/'
      || compter_en_tant_que(p_user, format('select count(*)::int from messages where remplacant_id = %L', p_fiche)) || '/'
      || compter_en_tant_que(p_user, format('select count(*)::int from evenements_fil where remplacant_id = %L', p_fiche))
$$;

select g_swend(now() + interval '1 hour') as p13 \gset
-- Côté David : Yann accepte puis se désiste, Walter refuse.
select ajouter_fiche(:'D', :'p13', 'destinataire', 'Yann', '0600000008') as y13 \gset
select ajouter_fiche(:'D', :'p13', 'destinataire', 'Walter', '0600000007') as w13 \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'y13') \gset
select g_rpc(:'Y', 'repondre_demande_remplacement', :'y13', 'true') \gset
select g_rpc(:'Y', 'se_desister_du_remplacement', :'y13') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'w13') \gset
select g_rpc(:'W', 'repondre_demande_remplacement', :'w13', 'false') \gset
-- Xavier : demande en attente côté David.
select ajouter_fiche(:'D', :'p13', 'destinataire', 'Xavier', '0600000009') as x13 \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'x13') \gset
-- Côté Eliot : Thomas sollicité, puis Kevin accepte (sélectionné, la demande
-- de Thomas est close), Camille prévue (a écrit).
select ajouter_fiche(:'E', :'p13', 'initiateur', 'Kevin', '0600000003') as k13 \gset
select ajouter_fiche(:'E', :'p13', 'initiateur', 'Camille', '0600000004') as c13 \gset
select ajouter_fiche(:'E', :'p13', 'initiateur', 'Thomas', '0600000005') as t13 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'t13') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k13') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k13', 'true') \gset
select g_ecrire(:'C', :'c13', 'Je suis là si besoin') \gset
select verifier('M', 'préparation : Kevin sélectionné, Thomas clos, Xavier en attente, Walter a refusé, Yann s''est désisté',
  statut_fiche(:'k13') = 'acceptee+sel' and statut_fiche(:'t13') = 'cloturee' and statut_fiche(:'x13') = 'envoyee'
  and statut_fiche(:'w13') = 'refusee' and statut_fiche(:'y13') = 'desistee'
  and (select statut from pactes where id = :'p13') = 'confirme');

-- Avant H : chacun garde les accès de son rôle.
select verifier('M', 'avant H : Kevin (sélectionné) → Swend, fiche, conversation', g_acces(:'K', :'p13', :'k13') = '1/1/0/2', g_acces(:'K', :'p13', :'k13'));
select verifier('M', 'avant H : Camille (prévue) → Swend, fiche, son message', g_acces(:'C', :'p13', :'c13') = '1/1/1/0', g_acces(:'C', :'p13', :'c13'));
select verifier('M', 'avant H : Thomas (demande close) → Swend, fiche, événements', g_acces(:'T', :'p13', :'t13') = '1/1/0/2', g_acces(:'T', :'p13', :'t13'));
select verifier('M', 'avant H : Xavier (sollicité) → Swend, fiche, demande', g_acces(:'X', :'p13', :'x13') = '1/1/0/1', g_acces(:'X', :'p13', :'x13'));
select verifier('M', 'avant H : Walter (a refusé) → Swend, fiche', g_acces(:'W', :'p13', :'w13') = '1/1/0/2', g_acces(:'W', :'p13', :'w13'));
select verifier('M', 'avant H : Yann (désisté) → Swend, fiche', g_acces(:'Y', :'p13', :'y13') = '1/1/0/3', g_acces(:'Y', :'p13', :'y13'));
select verifier('M', 'avant H : Zoé (extérieure) → rien', g_acces(:'Z', :'p13', :'k13') = '0/0/0/0');
select verifier('M', 'avant H : David ne voit rien du côté d''Eliot', g_acces(:'D', :'p13', :'c13') = '1/0/0/0', g_acces(:'D', :'p13', :'c13'));

select g_dater(:'p13', now() - interval '1 second');
select figer_swends_passes() \gset
-- Après H : titulaires et remplaçant sélectionné seulement.
select verifier('M', 'après H : Eliot garde le Swend et toutes les conversations de son côté',
  g_acces(:'E', :'p13', :'k13') = '1/1/0/3' and g_acces(:'E', :'p13', :'c13') = '1/1/1/1' and g_acces(:'E', :'p13', :'t13') = '1/1/0/3',
  g_acces(:'E', :'p13', :'k13') || ' ' || g_acces(:'E', :'p13', :'c13') || ' ' || g_acces(:'E', :'p13', :'t13'));
select verifier('M', 'après H : David garde le Swend et ses conversations (Walter, Yann)',
  g_acces(:'D', :'p13', :'w13') = '1/1/0/3' and g_acces(:'D', :'p13', :'y13') = '1/1/0/4',
  g_acces(:'D', :'p13', :'w13') || ' ' || g_acces(:'D', :'p13', :'y13'));
select verifier('M', 'après H : Kevin (sélectionné) garde Swend, fiche et conversation', g_acces(:'K', :'p13', :'k13') = '1/1/0/3', g_acces(:'K', :'p13', :'k13'));
select verifier('M', 'après H : Camille (prévue) n''a plus accès', g_acces(:'C', :'p13', :'c13') = '0/0/0/0', g_acces(:'C', :'p13', :'c13'));
select verifier('M', 'après H : Thomas (demande close) n''a plus accès', g_acces(:'T', :'p13', :'t13') = '0/0/0/0', g_acces(:'T', :'p13', :'t13'));
select verifier('M', 'après H : Xavier (sollicité, demande close à H) n''a plus accès',
  g_acces(:'X', :'p13', :'x13') = '0/0/0/0' and statut_fiche(:'x13') = 'cloturee', g_acces(:'X', :'p13', :'x13'));
select verifier('M', 'après H : Walter (a refusé) n''a plus accès', g_acces(:'W', :'p13', :'w13') = '0/0/0/0', g_acces(:'W', :'p13', :'w13'));
select verifier('M', 'après H : Yann (désisté) n''a plus accès', g_acces(:'Y', :'p13', :'y13') = '0/0/0/0', g_acces(:'Y', :'p13', :'y13'));
select verifier('M', 'après H : Zoé (extérieure) → rien', g_acces(:'Z', :'p13', :'k13') = '0/0/0/0');
select verifier('M', 'après H : les données restent en base (fiches et message)',
  (select count(*) from remplacants where pacte_id = :'p13') = 6
  and (select count(*) from messages where remplacant_id = :'c13') = 1);

-- Même personne des deux côtés : Kevin sollicité par David, puis il prend la
-- place d'Eliot. Après H : le Swend et sa fiche côté Eliot, pas l'autre.
select g_swend(now() + interval '1 hour') as p15 \gset
select ajouter_fiche(:'D', :'p15', 'destinataire', 'Kevin', '0600000003') as kd15 \gset
select ajouter_fiche(:'E', :'p15', 'initiateur', 'Kevin', '0600000003') as ke15 \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'kd15') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ke15') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'ke15', 'true') \gset
select g_dater(:'p15', now() - interval '1 second');
select verifier('M', 'même personne des deux côtés, après H : fiche sélectionnée visible, l''autre non',
  g_acces(:'K', :'p15', :'ke15') like '1/1/%' and g_acces(:'K', :'p15', :'kd15') = '1/0/0/0',
  g_acces(:'K', :'p15', :'ke15') || ' ' || g_acces(:'K', :'p15', :'kd15'));

-- Annulation (avant H) : même règle, immédiatement.
select g_swend(now() + interval '1 day') as p14 \gset
select ajouter_fiche(:'E', :'p14', 'initiateur', 'Kevin', '0600000003') as k14 \gset
select ajouter_fiche(:'E', :'p14', 'initiateur', 'Camille', '0600000004') as c14 \gset
select ajouter_fiche(:'D', :'p14', 'destinataire', 'Walter', '0600000007') as w14 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k14') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k14', 'true') \gset
select g_ecrire(:'C', :'c14', 'Coucou') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'w14') \gset
select g_rpc(:'W', 'repondre_demande_remplacement', :'w14', 'false') \gset
select g_rpc(:'D', 'annuler_swend', :'p14') \gset
select verifier('M', 'annulé : Swend annulé par David', (select statut from pactes where id = :'p14') = 'annule');
select verifier('M', 'annulé : Eliot garde le Swend et ses conversations',
  g_acces(:'E', :'p14', :'k14') like '1/1/%' and g_acces(:'E', :'p14', :'c14') = '1/1/1/0',
  g_acces(:'E', :'p14', :'c14'));
select verifier('M', 'annulé : Kevin (sélectionné) garde Swend et conversation', g_acces(:'K', :'p14', :'k14') like '1/1/%', g_acces(:'K', :'p14', :'k14'));
select verifier('M', 'annulé : Camille (prévue) et Walter (a refusé) n''ont plus accès',
  g_acces(:'C', :'p14', :'c14') = '0/0/0/0' and g_acces(:'W', :'p14', :'w14') = '0/0/0/0',
  g_acces(:'C', :'p14', :'c14') || ' ' || g_acces(:'W', :'p14', :'w14'));
select verifier('M', 'annulé : David garde sa conversation avec Walter', g_acces(:'D', :'p14', :'w14') like '1/1/%');

-- Double remplacement : les deux remplaçants sélectionnés gardent l'accès.
select g_swend(now() + interval '1 day') as p16 \gset
select ajouter_fiche(:'E', :'p16', 'initiateur', 'Kevin', '0600000003') as k16 \gset
select ajouter_fiche(:'D', :'p16', 'destinataire', 'Walter', '0600000007') as w16 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k16') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'w16') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k16', 'true') \gset
select g_rpc(:'W', 'repondre_demande_remplacement', :'w16', 'true') \gset
select verifier('M', 'double remplacement : Swend annulé, les deux remplaçants sélectionnés gardent l''accès',
  (select statut from pactes where id = :'p16') = 'annuleDoubleAbsence'
  and g_acces(:'K', :'p16', :'k16') like '1/1/%' and g_acces(:'W', :'p16', :'w16') like '1/1/%'
  and g_acces(:'K', :'p16', :'w16') = '1/0/0/0');

-- Fonctions d'accès : jamais exécutables sans compte.
select verifier('M', 'fonctions d''accès : exécutables par authenticated seulement',
  has_function_privilege('authenticated', 'public.personne_de_confiance_a_acces(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.personne_de_confiance_a_acces(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.fiche_de_confiance_accessible(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.fil_lisible(uuid)', 'execute'));

-- ===================================================================
-- N. Numéro du titulaire pour sa personne de confiance
--    (telephone_titulaire_accessible ; ancienne fonction plus exécutable)
-- ===================================================================
-- Numéro obtenu par p_user pour la fiche (vide si refusé, « ERREUR » si la
-- fonction n'est pas exécutable).
create or replace function g_tel(p_user uuid, p_fonction text, p_fiche uuid) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
  begin
    execute format('select %s(%L)', p_fonction, p_fiche) into v;
  exception when insufficient_privilege then
    v := 'ERREUR';
  end;
  execute 'reset role';
  return coalesce(v, '');
end $$;

select g_swend(now() + interval '1 hour') as p17 \gset
select ajouter_fiche(:'E', :'p17', 'initiateur', 'Kevin', '0600000003') as k17 \gset
select ajouter_fiche(:'E', :'p17', 'initiateur', 'Camille', '0600000004') as c17 \gset
select ajouter_fiche(:'E', :'p17', 'initiateur', 'Thomas', '0600000005') as t17 \gset
select ajouter_fiche(:'D', :'p17', 'destinataire', 'Walter', '0600000007') as w17 \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'w17') \gset
select g_rpc(:'W', 'repondre_demande_remplacement', :'w17', 'false') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'c17') \gset
select g_rpc(:'E', 'retirer_remplacant', :'t17') \gset
-- Avant H : le rôle légitime fonctionne.
select verifier('N', 'avant H : Kevin (prévu) obtient le numéro d''Eliot', g_tel(:'K', 'telephone_titulaire_accessible', :'k17') = '0600000001',
  g_tel(:'K', 'telephone_titulaire_accessible', :'k17'));
select verifier('N', 'avant H : Camille (sollicitée) obtient le numéro d''Eliot', g_tel(:'C', 'telephone_titulaire_accessible', :'c17') = '0600000001');
select verifier('N', 'avant H : Walter (a refusé) obtient le numéro de David', g_tel(:'W', 'telephone_titulaire_accessible', :'w17') = '0600000002');
select verifier('N', 'personne retirée : aucun numéro', g_tel(:'T', 'telephone_titulaire_accessible', :'t17') = '');
select verifier('N', 'fiche d''un autre : aucun numéro (Kevin sur la fiche de Camille, Zoé, David)',
  g_tel(:'K', 'telephone_titulaire_accessible', :'c17') = '' and g_tel(:'Z', 'telephone_titulaire_accessible', :'k17') = ''
  and g_tel(:'D', 'telephone_titulaire_accessible', :'k17') = '');
select verifier('N', 'ancienne fonction telephone_titulaire_du_pacte : plus exécutable par l''app',
  g_tel(:'K', 'telephone_titulaire_du_pacte', :'k17') = 'ERREUR'
  and not has_function_privilege('anon', 'public.telephone_titulaire_du_pacte(uuid)', 'execute'));
-- Kevin accepte, puis H passe.
select g_rpc(:'E', 'annuler_demande_remplacement', :'c17') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k17') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'c17') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k17', 'true') \gset
select g_dater(:'p17', now() - interval '1 second');
select verifier('N', 'après H : Kevin (sélectionné) obtient toujours le numéro d''Eliot', g_tel(:'K', 'telephone_titulaire_accessible', :'k17') = '0600000001');
select verifier('N', 'après H : Camille (demande close) n''obtient plus rien', g_tel(:'C', 'telephone_titulaire_accessible', :'c17') = '');
select verifier('N', 'après H : Walter (a refusé) n''obtient plus rien', g_tel(:'W', 'telephone_titulaire_accessible', :'w17') = '');
-- Annulation.
select g_swend(now() + interval '1 day') as p18 \gset
select ajouter_fiche(:'E', :'p18', 'initiateur', 'Kevin', '0600000003') as k18 \gset
select ajouter_fiche(:'E', :'p18', 'initiateur', 'Camille', '0600000004') as c18 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k18') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k18', 'true') \gset
select verifier('N', 'avant l''annulation : Camille (prévue) obtient le numéro', g_tel(:'C', 'telephone_titulaire_accessible', :'c18') = '0600000001');
select g_rpc(:'E', 'annuler_swend', :'p18') \gset
select verifier('N', 'annulé : Camille (prévue) n''obtient plus rien ; Kevin (sélectionné) oui',
  g_tel(:'C', 'telephone_titulaire_accessible', :'c18') = '' and g_tel(:'K', 'telephone_titulaire_accessible', :'k18') = '0600000001');
-- Avant scellage (D-019) : rien.
insert into pactes (id, statut, type, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
                    destinataire_nom, destinataire_telephone)
values ('00000000-0000-4000-9800-000000000019', 'enAttenteChoixDateDestinataire', 'diner', array[now() + interval '3 days'],
        null, '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', 'David D', '06 00 00 00 02');
select ajouter_fiche(:'E', '00000000-0000-4000-9800-000000000019', 'initiateur', 'Kevin', '0600000003') as k19 \gset
select verifier('N', 'avant scellage : aucun numéro (D-019)', g_tel(:'K', 'telephone_titulaire_accessible', :'k19') = '');

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
