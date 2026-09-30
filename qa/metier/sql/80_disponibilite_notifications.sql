-- D-008 (indisponibilité spontanée réversible) et D-015 (notifications des
-- actions directes). Utilise les outils de 10_imprevu.sql (verifier,
-- en_tant_que, compter_en_tant_que, statut_fiche, nouveau_swend, ajouter_fiche).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set T '00000000-0000-0000-0000-00000000000b'

create or replace function dispo(p_id uuid) returns text language sql as $$
  select statut_fiche(p_id) || case when indisponible_spontanement then '+indispo' else '' end
  from remplacants where id = p_id
$$;
create or replace function notifs_depuis(p_depuis bigint, p_profil uuid) returns text language sql as $$
  select coalesce(string_agg(corps, ' | ' order by id), '') from notifications_log
  where id > p_depuis and profile_id = p_profil
$$;

select coalesce(max(id), 0) as debut from notifications_log \gset

-- ===================================================================
-- S. Indisponibilité spontanée : états et permissions (D-008)
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset

select verifier('S', 'une fiche naît disponible', dispo(:'k') = 'null');
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('S', 'Kevin (simplement prévu) se déclare indisponible',
  en_tant_que(:'K', format('select signaler_indisponibilite(%L)', :'k')) = 'OK');
select verifier('S', 'drapeau posé, aucune demande créée (état distinct)', dispo(:'k') = 'null+indispo', dispo(:'k'));
select verifier('S', 'événement "indisponibilite_signalee" dans le fil',
  (select count(*) from evenements_fil where remplacant_id = :'k' and code = 'indisponibilite_signalee') = 1);
select verifier('S', 'Eliot notifié une fois', notifs_depuis(:n0, :'E') = 'Kevin ne sera pas disponible en cas d''imprévu pour ce Swend.', notifs_depuis(:n0, :'E'));
select verifier('S', 'personne d''autre notifiée', (select count(*) from notifications_log where id > :n0) = 1);
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('S', 'deuxième signalement sans effet (ni notification, ni événement en double)',
  en_tant_que(:'K', format('select signaler_indisponibilite(%L)', :'k')) = 'OK'
  and (select count(*) from notifications_log where id > :n0) = 0
  and (select count(*) from evenements_fil where remplacant_id = :'k') = 1);
select verifier('S', 'Eliot ne peut pas solliciter Kevin',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) like '%personne_indisponible%');
select verifier('S', 'Eliot ne peut pas le ré-ajouter pour contourner',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'Kev', 'A', '06 00 00 00 03')) like '%personne_deja_prevue%');
select verifier('S', 'Eliot ne peut pas lever l''indisponibilité de Kevin',
  en_tant_que(:'E', format('select signaler_disponibilite(%L)', :'k')) like '%Non autorisé%');
select verifier('S', 'Camille ne peut pas agir sur la fiche de Kevin',
  en_tant_que(:'C', format('select signaler_indisponibilite(%L)', :'k')) like '%Non autorisé%');
select verifier('S', 'David ne peut pas agir sur la fiche de Kevin',
  en_tant_que(:'D', format('select signaler_disponibilite(%L)', :'k')) like '%Non autorisé%');
select verifier('S', 'écriture directe du drapeau refusée',
  en_tant_que(:'K', format('update remplacants set indisponible_spontanement = false where id = %L', :'k')) like '%permission denied%');
select en_tant_que(:'E', format(
    'insert into remplacants (pacte_id, cote, prenom, nom, telephone, email, indisponible_spontanement) values (%L, %L, %L, %L, %L, %L, true)',
    :'p', 'initiateur', 'Forge', 'X', '0600000098', '')) as r \gset
select verifier('S', 'INSERT forgé "déjà indisponible" neutralisé',
  :'r' = 'OK' and (select dispo(id) from remplacants where pacte_id = :'p' and prenom = 'Forge') = 'null', :'r');
select verifier('S', 'la fiche de Kevin côté David n''est pas touchée', dispo(:'kd') = 'null');
select verifier('S', 'David peut toujours solliciter Kevin de son côté',
  en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'kd')) = 'OK');
select verifier('S', 'David annule (Kevin notifié de l''annulation)',
  en_tant_que(:'D', format('select annuler_demande_remplacement(%L)', :'kd')) = 'OK');

select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('S', 'Kevin se déclare finalement disponible',
  en_tant_que(:'K', format('select signaler_disponibilite(%L)', :'k')) = 'OK' and dispo(:'k') = 'null');
select verifier('S', 'événement "disponibilite_retablie"',
  (select count(*) from evenements_fil where remplacant_id = :'k' and code = 'disponibilite_retablie') = 1);
select verifier('S', 'Eliot notifié du retour', notifs_depuis(:n0, :'E') = 'Kevin est de nouveau disponible en cas d''imprévu pour ce Swend.', notifs_depuis(:n0, :'E'));
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('S', 'second retour sans effet',
  en_tant_que(:'K', format('select signaler_disponibilite(%L)', :'k')) = 'OK'
  and (select count(*) from notifications_log where id > :n0) = 0);
select verifier('S', 'Kevin de nouveau sollicitable',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) = 'OK' and dispo(:'k') = 'envoyee');
select verifier('S', 'demande en cours : impossible de se déclarer indisponible (il doit répondre)',
  en_tant_que(:'K', format('select signaler_indisponibilite(%L)', :'k')) like '%demande_non_active%');

-- Le refus reste définitif, même via l'indisponibilité spontanée.
select verifier('S', 'Kevin refuse', en_tant_que(:'K', format('select repondre_demande_remplacement(%L, false)', :'k')) = 'OK');
select verifier('S', 'refus : impossible de passer en indisponibilité spontanée',
  en_tant_que(:'K', format('select signaler_indisponibilite(%L)', :'k')) like '%demande_non_active%');
select verifier('S', 'refus : "je suis finalement disponible" ne rouvre rien',
  en_tant_que(:'K', format('select signaler_disponibilite(%L)', :'k')) = 'OK' and dispo(:'k') = 'refusee');
select verifier('S', 'refus : toujours non sollicitable',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) like '%personne_indisponible%');

-- Le désistement reste définitif.
select verifier('S', 'Thomas se déclare indisponible (reste ainsi pendant la suite)',
  en_tant_que(:'T', format('select signaler_indisponibilite(%L)', :'t')) = 'OK');
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'c')) as r \gset
select verifier('S', 'Camille accepte', en_tant_que(:'C', format('select repondre_demande_remplacement(%L, true)', :'c')) = 'OK');
select verifier('S', 'place prise : Camille ne peut pas se déclarer indisponible (elle doit se désister)',
  en_tant_que(:'C', format('select signaler_indisponibilite(%L)', :'c')) like '%demande_non_active%');
select verifier('S', 'Thomas (indisponible spontanément) n''est pas clôturé par l''acceptation', dispo(:'t') = 'null+indispo', dispo(:'t'));
select verifier('S', 'Camille se désiste', en_tant_que(:'C', format('select se_desister_du_remplacement(%L)', :'c')) = 'OK');
select verifier('S', 'désistement : impossible de passer en indisponibilité spontanée',
  en_tant_que(:'C', format('select signaler_indisponibilite(%L)', :'c')) like '%demande_non_active%');
select verifier('S', 'désistement : "je suis finalement disponible" ne rouvre rien',
  en_tant_que(:'C', format('select signaler_disponibilite(%L)', :'c')) = 'OK' and dispo(:'c') = 'desistee');
select verifier('S', 'désistement : Thomas reste indisponible spontanément', dispo(:'t') = 'null+indispo');
select verifier('S', 'Thomas redevient disponible puis sollicitable',
  en_tant_que(:'T', format('select signaler_disponibilite(%L)', :'t')) = 'OK'
  and en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'t')) = 'OK');

update pactes set statut = 'annule' where id = :'p';
select verifier('S', 'Swend annulé : plus aucune déclaration possible',
  en_tant_que(:'K', format('select signaler_indisponibilite(%L)', :'kd')) like '%swend_inactif%');

-- Confidentialité
select verifier('S', 'David ne lit ni la fiche ni son drapeau côté Eliot',
  compter_en_tant_que(:'D', format('select count(*) from remplacants where pacte_id = %L and cote = %L', :'p', 'initiateur')) = 0);
select verifier('S', 'David ne lit aucun événement côté Eliot',
  compter_en_tant_que(:'D', format('select count(*) from evenements_fil e join remplacants r on r.id = e.remplacant_id where r.pacte_id = %L and r.cote = %L', :'p', 'initiateur')) = 0);
-- D-023a : le Swend est annulé ; Kevin, seulement prévu, n'y a plus accès.
select verifier('S', 'Swend annulé : Kevin (seulement prévu) ne lit plus sa fiche (D-023a)',
  compter_en_tant_que(:'K', format('select count(*) from remplacants where id = %L', :'k')) = 0);

-- ===================================================================
-- N. Notifications des actions directes (D-015)
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset

select coalesce(max(id), 0) as n0 from notifications_log \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select verifier('N', 'demande envoyée : Kevin notifié une seule fois (inchangé), Eliot rien',
  notifs_depuis(:n0, :'K') = 'Eliot E te demande de prendre sa place pour un Swend.'
  and (select count(*) from notifications_log where id > :n0) = 1);

select coalesce(max(id), 0) as n0 from notifications_log \gset
select en_tant_que(:'E', format('select annuler_demande_remplacement(%L)', :'k')) as r \gset
select verifier('N', 'annulation : Kevin notifié', notifs_depuis(:n0, :'K') = 'Eliot a annulé sa demande.', notifs_depuis(:n0, :'K'));
select verifier('N', 'annulation : payload vers la conversation',
  (select data->>'type' = 'chat' and data->>'remplacant_id' = :'k' from notifications_log where id > :n0 and profile_id = :'K'));
select verifier('N', 'annulation : événement dans le fil',
  (select count(*) from evenements_fil where remplacant_id = :'k' and code = 'demande_annulee') = 1);

select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'t')) as r \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select en_tant_que(:'T', format('select repondre_demande_remplacement(%L, false)', :'t')) as r \gset
select verifier('N', 'refus : Eliot notifié, seul', notifs_depuis(:n0, :'E') = 'Thomas ne peut pas prendre votre place.'
  and (select count(*) from notifications_log where id > :n0) = 1, notifs_depuis(:n0, :'E'));
select verifier('N', 'refus : payload vers la conversation avec Thomas',
  (select data->>'remplacant_id' = :'t' and data->>'nom_interlocuteur' = 'Thomas X' from notifications_log where id > :n0 and profile_id = :'E'));

select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'c')) as r \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) as r \gset
select verifier('N', 'acceptation : Eliot notifié une fois', notifs_depuis(:n0, :'E') = 'Kevin a accepté de prendre votre place.', notifs_depuis(:n0, :'E'));
select verifier('N', 'acceptation : Camille (clôturée) notifiée une fois, sans savoir qui (inchangé)',
  notifs_depuis(:n0, :'C') = 'C''est bon, quelqu''un a pu prendre la place.');
select verifier('N', 'acceptation : aucune autre notification (Kevin ne se notifie pas lui-même)',
  (select count(*) from notifications_log where id > :n0) = 2);

select coalesce(max(id), 0) as n0 from notifications_log \gset
select en_tant_que(:'K', format('select se_desister_du_remplacement(%L)', :'k')) as r \gset
select verifier('N', 'désistement : Eliot notifié', notifs_depuis(:n0, :'E') = 'Kevin ne peut finalement plus prendre votre place.', notifs_depuis(:n0, :'E'));
select verifier('N', 'désistement : la réouverture de Camille ne notifie personne d''autre',
  (select count(*) from notifications_log where id > :n0) = 1 and dispo(:'c') = 'null');

-- Même personne des deux côtés : aucune notification révélatrice à David.
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'ke')) as r \gset
select en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'kd')) as r \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'ke')) as r \gset
select verifier('N', 'deux côtés : acceptation côté Eliot → Eliot seul notifié',
  notifs_depuis(:n0, :'E') = 'Kevin a accepté de prendre votre place.'
  and (select count(*) from notifications_log where id > :n0) = 1);
select en_tant_que(:'K', format('select se_desister_du_remplacement(%L)', :'ke')) as r \gset
select verifier('N', 'deux côtés : rien pour David (clôture puis réouverture de sa fiche)',
  notifs_depuis(:n0, :'D') = '');

select verifier('N', 'David n''a reçu aucune notification pendant tout ce fichier', notifs_depuis(:debut, :'D') = '', notifs_depuis(:debut, :'D'));

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
