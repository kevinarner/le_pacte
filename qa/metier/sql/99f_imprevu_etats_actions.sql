-- « En cas d'imprévu », lot 1 : états et actions (D-027). Utilise les outils
-- de 10_imprevu.sql (verifier, en_tant_que, ajouter_fiche, nouveau_swend,
-- statut_fiche) et de 98_gel_a_h.sql (g_swend, g_dater, g_rpc, g_push,
-- g_nb_push, g_n0, g_codes). Swends Eliot (initiateur) / David
-- (destinataire) ; Tom n'a pas de compte (aucune push possible).
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
-- Envoi groupé en tant qu'un utilisateur : « prénom:canal,… » (ordre des
-- prénoms), ou le message d'erreur.
create or replace function ia_envoyer(p_user uuid, p_ids uuid[]) returns text
language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
  begin
    execute 'select string_agg(r.prenom || '':'' || e.canal, '','' order by r.prenom)
             from envoyer_demandes_remplacement($1) e join remplacants r on r.id = e.remplacant_id'
      into v using p_ids;
  exception when others then
    v := sqlerrm;
  end;
  execute 'reset role';
  return v;
end $$;
-- plpgsql (jamais intégrées à la requête appelante) : chaque appel relit
-- l'état réel, même dans la vérification qui suit l'action testée.
create or replace function ia_etat(p uuid, p_cote text) returns text language plpgsql as $$
begin
  return etat_cote_titulaire(p, p_cote);
end $$;
create or replace function ia_declare(p uuid, p_cote text) returns boolean language plpgsql as $$
begin
  return exists (select 1 from imprevus_declares where pacte_id = p and cote = p_cote);
end $$;
create or replace function ia_renvoyer(p_id uuid) returns boolean language sql as $$
  select message_a_renvoyer from remplacants where id = p_id
$$;
-- Instantané des fiches d'un Swend (pour vérifier qu'un refus ne change rien).
create or replace function ia_photo(p uuid) returns text language sql as $$
  select string_agg(prenom || '=' || statut_fiche(id) || case when message_a_renvoyer then '+msg' else '' end,
                    ',' order by cote, prenom)
  from remplacants where pacte_id = p
$$;

-- ===================================================================
-- A. Envoi groupé : personnes avec et sans compte, tout ou rien
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Tom', '0711223344') as tom \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select verifier('A', 'avant tout envoi : côté normal, aucune déclaration',
  ia_etat(:'p', 'initiateur') = 'normal' and not ia_declare(:'p', 'initiateur'));

select g_n0() as n0 \gset
select verifier('A', 'groupe refusé si une personne est indisponible (Thomas a déjà refusé) : rien ne part',
  g_rpc(:'E', 'envoyer_demande_remplacement', :'t') = 'OK'
  and g_rpc(:'T', 'repondre_demande_remplacement', :'t', 'false') = 'OK');
select g_n0() as n0 \gset
select ia_photo(:'p') as photo \gset
select verifier('A', 'tout ou rien : Kevin + Thomas (refusé) → personne_indisponible, aucune fiche ni push',
  ia_envoyer(:'E', array[:'k', :'t']::uuid[]) like '%personne_indisponible%'
  and ia_photo(:'p') = :'photo' and g_nb_push(:n0) = 0);

select g_n0() as n0 \gset
select ia_envoyer(:'E', array[:'k', :'tom', :'c', :'k']::uuid[]) as res \gset
select verifier('A', 'Kevin + Tom + Camille (Kevin en double) : canal de remise de chacun',
  :'res' = 'Camille:notification,Kevin:notification,Tom:message', :'res');
select verifier('A', 'les trois demandes en attente',
  statut_fiche(:'k') = 'envoyee' and statut_fiche(:'c') = 'envoyee' and statut_fiche(:'tom') = 'envoyee');
select verifier('A', 'push « On a besoin de toi » à Kevin et Camille, une fois chacun ; rien d''autre',
  g_push(:n0, :'K') = 'On a besoin de toi|Eliot E te demande de prendre sa place pour un Swend.'
  and g_push(:n0, :'C') = 'On a besoin de toi|Eliot E te demande de prendre sa place pour un Swend.'
  and g_nb_push(:n0) = 2);
select verifier('A', 'Tom (sans compte) : pas de message à renvoyer à l''envoi initial',
  not ia_renvoyer(:'tom'));
select verifier('A', 'événement « demande envoyée » dans chaque conversation',
  g_codes(:'k') = 'demande_envoyee' and g_codes(:'c') = 'demande_envoyee' and g_codes(:'tom') = 'demande_envoyee');
select verifier('A', 'imprévu déclaré côté Eliot, jamais côté David',
  ia_declare(:'p', 'initiateur') and not ia_declare(:'p', 'destinataire')
  and ia_etat(:'p', 'initiateur') = 'cherche' and ia_etat(:'p', 'destinataire') = 'normal');
select verifier('A', 'une personne déjà en attente ne peut pas être sollicitée à nouveau',
  ia_envoyer(:'E', array[:'k']::uuid[]) like '%personne_indisponible%');

select verifier('A', 'liste vide → aucune_personne',
  ia_envoyer(:'E', array[]::uuid[]) like '%aucune_personne%'
  and ia_envoyer(:'E', null) like '%aucune_personne%');
select ajouter_fiche(:'D', :'p', 'destinataire', 'Zoé', '0600000006') as zd \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Zoé', '0600000006') as ze \gset
select verifier('A', 'deux côtés dans un même envoi → Non autorisé, rien ne part',
  ia_envoyer(:'E', array[:'ze', :'zd']::uuid[]) like '%Non autorisé%'
  and statut_fiche(:'ze') = 'null' and statut_fiche(:'zd') = 'null');
select verifier('A', 'David ne peut pas envoyer les demandes d''Eliot',
  ia_envoyer(:'D', array[:'ze']::uuid[]) like '%Non autorisé%');
select verifier('A', 'Kevin (personne de confiance) non plus',
  ia_envoyer(:'K', array[:'ze']::uuid[]) like '%Non autorisé%');
select verifier('A', 'fiche inconnue → Non autorisé',
  ia_envoyer(:'E', array[gen_random_uuid()]) like '%Non autorisé%');
select nouveau_swend() as p2 \gset
select ajouter_fiche(:'E', :'p2', 'initiateur', 'Kevin', '0600000003') as k2 \gset
select verifier('A', 'deux Swends dans un même envoi → Non autorisé',
  ia_envoyer(:'E', array[:'ze', :'k2']::uuid[]) like '%Non autorisé%' and statut_fiche(:'k2') = 'null');
select verifier('A', 'l''app n''écrit jamais directement la demande ni le message à renvoyer',
  en_tant_que(:'E', format('update remplacants set message_a_renvoyer = true where id = %L', :'tom')) like '%permission denied%');
select verifier('A', 'anon ne peut pas envoyer de demandes',
  not has_function_privilege('anon', 'public.envoyer_demandes_remplacement(uuid[])', 'execute')
  and has_function_privilege('authenticated', 'public.envoyer_demandes_remplacement(uuid[])', 'execute'));

-- Personne qui remplace déjà l'autre titulaire : refusée dans un groupe.
select nouveau_swend() as p3 \gset
select ajouter_fiche(:'E', :'p3', 'initiateur', 'Kevin', '0600000003') as ke3 \gset
select ajouter_fiche(:'D', :'p3', 'destinataire', 'Camille', '0600000004') as cd3 \gset
select ajouter_fiche(:'D', :'p3', 'destinataire', 'Thomas', '0600000005') as td3 \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'cd3') \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'cd3', 'true') \gset
select ajouter_fiche(:'E', :'p3', 'initiateur', 'Camille', '0600000004') as ce3 \gset
select verifier('A', 'Camille remplace David : groupe Kevin + Camille côté Eliot refusé, rien ne part',
  ia_envoyer(:'E', array[:'ke3', :'ce3']::uuid[]) like '%personne_indisponible%' and statut_fiche(:'ke3') = 'null');
select verifier('A', 'place prise : plus aucun envoi de ce côté (place_deja_prise)',
  ia_envoyer(:'D', array[:'td3']::uuid[]) like '%place_deja_prise%');
select en_tant_que(:'E', format('select retirer_remplacant(%L)', :'ke3')) \gset
select verifier('A', 'fiche retirée → demande_non_active',
  ia_envoyer(:'E', array[:'ke3']::uuid[]) like '%demande_non_active%');

-- Après H, Swend annulé.
select g_swend(now() + interval '2 days') as p4 \gset
select ajouter_fiche(:'E', :'p4', 'initiateur', 'Kevin', '0600000003') as k4 \gset
select g_dater(:'p4', now() - interval '1 minute');
select verifier('A', 'après H → swend_passe', ia_envoyer(:'E', array[:'k4']::uuid[]) like '%swend_passe%');
select g_swend(now() + interval '2 days') as p5 \gset
select ajouter_fiche(:'E', :'p5', 'initiateur', 'Kevin', '0600000003') as k5 \gset
select en_tant_que(:'E', format('select annuler_swend(%L)', :'p5')) \gset
select verifier('A', 'Swend annulé → swend_inactif', ia_envoyer(:'E', array[:'k5']::uuid[]) like '%swend_inactif%');

-- L'action d'une seule personne (app actuelle) suit la même règle.
select nouveau_swend() as p6 \gset
select ajouter_fiche(:'E', :'p6', 'initiateur', 'Tom', '0711223344') as tom6 \gset
select g_n0() as n0 \gset
select verifier('A', 'envoyer_demande_remplacement (une personne, sans compte) : demande en attente, aucune push, imprévu déclaré',
  g_rpc(:'E', 'envoyer_demande_remplacement', :'tom6') = 'OK' and statut_fiche(:'tom6') = 'envoyee'
  and g_nb_push(:n0) = 0 and ia_declare(:'p6', 'initiateur'));
select g_n0() as n0 \gset
select verifier('A', 'ajouter et demander (Zoé, a un compte) : push « On a besoin de toi », imprévu déclaré',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p6', 'initiateur', 'Zoé', 'Z', '0600000006')) = 'OK'
  and g_push(:n0, :'Z') = 'On a besoin de toi|Eliot E te demande de prendre sa place pour un Swend.'
  and g_nb_push(:n0) = 1);

-- ===================================================================
-- R. « Je peux finalement venir »
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Tom', '0711223344') as tom \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Zoé', '0600000006') as zd \gset
select verifier('R', 'sans imprévu → aucun_imprevu', g_rpc(:'E', 'je_peux_finalement_venir', :'p') like '%aucun_imprevu%');
select ia_envoyer(:'E', array[:'k', :'c', :'t', :'tom']::uuid[]) \gset
select g_rpc(:'T', 'repondre_demande_remplacement', :'t', 'false') \gset
select verifier('R', 'David (pas d''imprévu de son côté) → aucun_imprevu',
  g_rpc(:'D', 'je_peux_finalement_venir', :'p') like '%aucun_imprevu%');
select verifier('R', 'Kevin (personne de confiance) → Non autorisé',
  g_rpc(:'K', 'je_peux_finalement_venir', :'p') like '%Non autorisé%');
select g_n0() as n0 \gset
select verifier('R', 'Eliot peut finalement venir', g_rpc(:'E', 'je_peux_finalement_venir', :'p') = 'OK');
select verifier('R', 'demandes en attente closes (Kevin, Camille, Tom redeviennent prévus), refus conservé (Thomas)',
  statut_fiche(:'k') = 'null' and statut_fiche(:'c') = 'null' and statut_fiche(:'tom') = 'null'
  and statut_fiche(:'t') = 'refusee');
select verifier('R', 'côté Eliot : plus d''imprévu (rappels « repas »), malgré le refus de Thomas',
  not ia_declare(:'p', 'initiateur') and ia_etat(:'p', 'initiateur') = 'normal');
select verifier('R', 'push aux personnes qui attendaient une réponse, et à elles seules',
  g_push(:n0, :'K') = 'Plus besoin de répondre|Eliot pourra finalement être là pour ce Swend.'
  and g_push(:n0, :'C') = 'Plus besoin de répondre|Eliot pourra finalement être là pour ce Swend.'
  and g_nb_push(:n0) = 2);
select verifier('R', 'push vers la conversation de chacun',
  (select bool_and(data->>'type' = 'chat' and data->>'remplacant_id' in (:'k', :'c'))
   from notifications_log where id > :n0));
select verifier('R', 'événement « retour du titulaire » dans les conversations en attente seulement',
  g_codes(:'k') = 'demande_envoyee,retour_titulaire' and g_codes(:'tom') = 'demande_envoyee,retour_titulaire'
  and g_codes(:'t') = 'demande_envoyee,demande_refusee');
select verifier('R', 'Kevin ne peut plus accepter', g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'true') like '%demande_non_active%');
select verifier('R', 'Kevin lit toujours sa conversation et le retour d''Eliot',
  compter_en_tant_que(:'K', format('select count(*) from evenements_fil where remplacant_id = %L and code = %L', :'k', 'retour_titulaire')) = 1);
select verifier('R', 'David ne voit rien du côté d''Eliot',
  compter_en_tant_que(:'D', format('select count(*) from evenements_fil where remplacant_id in (%L, %L)', :'k', :'c')) = 0
  and g_push(:n0, :'D') = '');
select verifier('R', 'deux fois de suite → aucun_imprevu', g_rpc(:'E', 'je_peux_finalement_venir', :'p') like '%aucun_imprevu%');
select g_n0() as n0 \gset
select verifier('R', 'nouvel imprévu : Kevin et Camille de nouveau sollicitables, Thomas non',
  ia_envoyer(:'E', array[:'k', :'c']::uuid[]) = 'Camille:notification,Kevin:notification'
  and ia_envoyer(:'E', array[:'t']::uuid[]) like '%personne_indisponible%'
  and ia_declare(:'p', 'initiateur'));
select g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'true') \gset
select verifier('R', 'après une acceptation → place_deja_prise, rien ne bouge',
  g_rpc(:'E', 'je_peux_finalement_venir', :'p') like '%place_deja_prise%'
  and statut_fiche(:'k') = 'acceptee+sel' and ia_declare(:'p', 'initiateur'));
select g_rpc(:'K', 'se_desister_du_remplacement', :'k') \gset
select verifier('R', 'après un désistement, sans personne : « Je peux finalement venir » redevient possible',
  g_rpc(:'E', 'je_peux_finalement_venir', :'p') = 'OK' and ia_etat(:'p', 'initiateur') = 'normal'
  and statut_fiche(:'c') = 'null' and statut_fiche(:'k') = 'desistee');

select g_swend(now() + interval '2 days') as p4 \gset
select ajouter_fiche(:'E', :'p4', 'initiateur', 'Kevin', '0600000003') as k4 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k4') \gset
select g_dater(:'p4', now() - interval '1 minute');
select verifier('R', 'après H → swend_passe', g_rpc(:'E', 'je_peux_finalement_venir', :'p4') like '%swend_passe%');
select g_swend(now() + interval '2 days') as p5 \gset
select ajouter_fiche(:'E', :'p5', 'initiateur', 'Kevin', '0600000003') as k5 \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k5') \gset
select en_tant_que(:'E', format('select annuler_swend(%L)', :'p5')) \gset
select verifier('R', 'Swend annulé → swend_inactif', g_rpc(:'E', 'je_peux_finalement_venir', :'p5') like '%swend_inactif%');

-- ===================================================================
-- N. Refus : le titulaire n'est prévenu qu'au dernier
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Tom', '0711223344') as tom \gset
select ia_envoyer(:'E', array[:'k', :'c', :'tom']::uuid[]) \gset
select g_n0() as n0 \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'false') \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'c', 'false') \gset
select verifier('N', 'Tom (sans compte) toujours en attente : aucun refus notifié à Eliot',
  g_push(:n0, :'E') = '' and g_nb_push(:n0) = 0);
select g_rpc(:'E', 'annuler_demande_remplacement', :'tom') \gset
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ia_envoyer(:'E', array[:'k', :'c']::uuid[]) \gset
select g_n0() as n0 \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'false') \gset
select verifier('N', 'premier refus (Camille attend encore) : rien', g_nb_push(:n0) = 0);
select g_rpc(:'C', 'repondre_demande_remplacement', :'c', 'false') \gset
select verifier('N', 'dernier refus : une push à Eliot, vers la fiche du Swend',
  g_push(:n0, :'E') = 'Personne n’est disponible pour l’instant|Tu peux solliciter quelqu’un d’autre.'
  and g_nb_push(:n0) = 1
  and (select data->>'type' = 'pacte' and data->>'pacte_id' = :'p' from notifications_log where id > :n0));
select verifier('N', 'tout le monde a refusé : Eliot est toujours en imprévu',
  ia_etat(:'p', 'initiateur') = 'cherche');

-- ===================================================================
-- D. Désistement : réactivation automatique
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Tom', '0711223344') as tom \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Zoé', '0600000006') as z \gset
select ia_envoyer(:'E', array[:'k', :'c', :'t', :'tom']::uuid[]) \gset
select g_rpc(:'T', 'repondre_demande_remplacement', :'t', 'false') \gset
select g_n0() as n0 \gset
select verifier('D', 'Camille accepte', g_rpc(:'C', 'repondre_demande_remplacement', :'c', 'true') = 'OK');
select verifier('D', 'Kevin et Tom clôturés, Thomas refusé, Zoé jamais sollicitée',
  statut_fiche(:'k') = 'cloturee' and statut_fiche(:'tom') = 'cloturee'
  and statut_fiche(:'t') = 'refusee' and statut_fiche(:'z') = 'null');
select verifier('D', 'acceptation : Eliot « Camille a accepté », Kevin « Plus besoin de répondre », rien d''autre',
  g_push(:n0, :'E') = 'Camille a accepté|Camille sera là à ta place le jour J.'
  and g_push(:n0, :'K') = 'Plus besoin de répondre|La place a été prise pour ce Swend.'
  and g_nb_push(:n0) = 2);
select verifier('D', 'la clôture se souvient de l''acceptation de Camille',
  (select count(*) from clotures_demandes where fiche_acceptee = :'c' and motif = 'acceptation') = 2);
select verifier('D', 'Kevin ne peut plus accepter (place_deja_prise)',
  g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'true') like '%place_deja_prise%');

select g_n0() as n0 \gset
select verifier('D', 'Camille se désiste', g_rpc(:'C', 'se_desister_du_remplacement', :'c') = 'OK');
select verifier('D', 'Kevin et Tom de nouveau en attente ; Thomas toujours refusé ; Zoé toujours seulement prévue',
  statut_fiche(:'k') = 'envoyee' and statut_fiche(:'tom') = 'envoyee'
  and statut_fiche(:'t') = 'refusee' and statut_fiche(:'z') = 'null' and statut_fiche(:'c') = 'desistee', ia_photo(:'p'));
select verifier('D', 'push : Eliot (désistement) et Kevin (réactivé), une chacun ; rien à Tom ni à Thomas',
  g_push(:n0, :'E') = 'Camille ne peut finalement plus venir|Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.'
  and g_push(:n0, :'K') = 'Ta réponse est finalement attendue|La place est à nouveau disponible pour ce Swend.'
  and g_push(:n0, :'T') = '' and g_nb_push(:n0) = 2);
select verifier('D', 'push de désistement vers la conversation avec Camille',
  (select data->>'type' = 'chat' and data->>'remplacant_id' = :'c' from notifications_log where id > :n0 and profile_id = :'E'));
select verifier('D', 'Tom (sans compte) : réactivé, mais avec un message à renvoyer (jamais en silence)',
  ia_renvoyer(:'tom') and not ia_renvoyer(:'k'));
select verifier('D', 'Eliot lit le message à renvoyer sur la fiche de Tom (RLS)',
  compter_en_tant_que(:'E', format('select count(*) from remplacants where id = %L and message_a_renvoyer', :'tom')) = 1);
select verifier('D', 'événement « demande réactivée » pour Kevin et Tom',
  g_codes(:'k') = 'demande_envoyee,demande_cloturee,demande_reactivee'
  and g_codes(:'tom') = 'demande_envoyee,demande_cloturee,demande_reactivee');
select verifier('D', 'mémoire de clôture effacée après réactivation',
  (select count(*) from clotures_demandes where remplacant_id in (:'k', :'tom')) = 0);
select verifier('D', 'Eliot toujours en imprévu ; David jamais notifié',
  ia_etat(:'p', 'initiateur') = 'cherche' and g_push(:n0, :'D') = '');
select verifier('D', 'marquer le message renvoyé : David → Non autorisé, Kevin → Non autorisé',
  g_rpc(:'D', 'marquer_message_renvoye', :'tom') like '%Non autorisé%'
  and g_rpc(:'K', 'marquer_message_renvoye', :'tom') like '%Non autorisé%' and ia_renvoyer(:'tom'));
select verifier('D', 'Eliot a renvoyé le message : l''action disparaît, la demande reste en attente',
  g_rpc(:'E', 'marquer_message_renvoye', :'tom') = 'OK' and not ia_renvoyer(:'tom') and statut_fiche(:'tom') = 'envoyee');
select verifier('D', 'Kevin peut accepter à nouveau',
  g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'true') = 'OK' and statut_fiche(:'k') = 'acceptee+sel'
  and statut_fiche(:'tom') = 'cloturee');
select g_n0() as n0 \gset
select g_rpc(:'K', 'se_desister_du_remplacement', :'k') \gset
select verifier('D', 'second désistement : Tom réactivé de nouveau (message à renvoyer), Camille et Thomas non',
  statut_fiche(:'tom') = 'envoyee' and ia_renvoyer(:'tom')
  and statut_fiche(:'c') = 'desistee' and statut_fiche(:'t') = 'refusee');
select verifier('D', 'Eliot : « Les personnes qui n’avaient pas encore répondu… » (Tom en attente)',
  g_push(:n0, :'E') = 'Kevin ne peut finalement plus venir|Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.'
  and g_nb_push(:n0) = 1);
select g_rpc(:'E', 'je_peux_finalement_venir', :'p') \gset
select verifier('D', 'Tom n''attend plus de réponse : le message à renvoyer disparaît',
  statut_fiche(:'tom') = 'null' and not ia_renvoyer(:'tom'));

-- Personne n'attendait de réponse : « Tu peux solliciter quelqu'un d'autre ».
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'true') \gset
select g_n0() as n0 \gset
select g_rpc(:'K', 'se_desister_du_remplacement', :'k') \gset
select verifier('D', 'désistement sans demande en attente avant : « Tu peux solliciter quelqu’un d’autre. »',
  g_push(:n0, :'E') = 'Kevin ne peut finalement plus venir|Tu peux solliciter quelqu’un d’autre.'
  and g_nb_push(:n0) = 1 and statut_fiche(:'c') = 'null' and ia_etat(:'p', 'initiateur') = 'cherche');

-- Une personne retirée entre-temps n'est pas réactivée.
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ia_envoyer(:'E', array[:'k', :'c']::uuid[]) \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'c', 'true') \gset
select verifier('D', 'Kevin (clôturé) peut être retiré', g_rpc(:'E', 'retirer_remplacant', :'k') = 'OK');
select g_n0() as n0 \gset
select g_rpc(:'C', 'se_desister_du_remplacement', :'c') \gset
select verifier('D', 'fiche retirée : jamais réactivée, aucune push à Kevin',
  statut_fiche(:'k') = 'cloturee' and g_push(:n0, :'K') = ''
  and g_push(:n0, :'E') = 'Camille ne peut finalement plus venir|Tu peux solliciter quelqu’un d’autre.');

-- ===================================================================
-- M. Même personne des deux côtés (D-012)
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Thomas', '0600000005') as td \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ke') \gset
select ia_envoyer(:'D', array[:'kd', :'td']::uuid[]) \gset
select g_n0() as n0 \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'ke', 'true') \gset
select verifier('M', 'Kevin accepte la place d''Eliot : sa demande côté David close sans push, mémoire « en attente »',
  statut_fiche(:'kd') = 'cloturee' and g_push(:n0, :'K') = '' and g_push(:n0, :'D') = ''
  and (select motif || '/' || statut_avant from clotures_demandes where remplacant_id = :'kd') = 'autre_cote/envoyee');
select verifier('M', 'l''app ne lit jamais la mémoire des clôtures (elle révélerait qui remplace l''autre côté)',
  en_tant_que(:'D', 'select count(*) from clotures_demandes') like '%permission denied%'
  and en_tant_que(:'E', 'select count(*) from clotures_demandes') like '%permission denied%');
select g_n0() as n0 \gset
select g_rpc(:'K', 'se_desister_du_remplacement', :'ke') \gset
select verifier('M', 'Kevin se désiste côté Eliot : la demande de David l''attend de nouveau',
  statut_fiche(:'kd') = 'envoyee' and statut_fiche(:'ke') = 'desistee');
select verifier('M', 'push : Kevin (« Ta réponse est finalement attendue », une seule) et Eliot ; rien à David',
  g_push(:n0, :'K') = 'Ta réponse est finalement attendue|La place est à nouveau disponible pour ce Swend.'
  and g_push(:n0, :'E') = 'Kevin ne peut finalement plus venir|Tu peux solliciter quelqu’un d’autre.'
  and g_push(:n0, :'D') = '' and g_nb_push(:n0) = 2);
select verifier('M', 'push de Kevin vers sa conversation avec David',
  (select data->>'remplacant_id' = :'kd' from notifications_log where id > :n0 and profile_id = :'K'));
select verifier('M', 'Kevin peut maintenant accepter la place de David',
  g_rpc(:'K', 'repondre_demande_remplacement', :'kd', 'true') = 'OK');

-- Kevin seulement prévu côté David : il redevient simplement prévu.
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Thomas', '0600000005') as td \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'td') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ke') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'ke', 'true') \gset
select g_n0() as n0 \gset
select g_rpc(:'K', 'se_desister_du_remplacement', :'ke') \gset
select verifier('M', 'fiche seulement prévue côté David : redevient prévue, sans push à Kevin',
  statut_fiche(:'kd') = 'null' and g_push(:n0, :'K') = '');

-- David pourra finalement venir pendant que Kevin remplace Eliot.
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Thomas', '0600000005') as td \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ke') \gset
select ia_envoyer(:'D', array[:'kd', :'td']::uuid[]) \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'ke', 'true') \gset
select verifier('M', 'David peut finalement venir', g_rpc(:'D', 'je_peux_finalement_venir', :'p') = 'OK'
  and statut_fiche(:'td') = 'null' and statut_fiche(:'kd') = 'cloturee');
select g_n0() as n0 \gset
select g_rpc(:'K', 'se_desister_du_remplacement', :'ke') \gset
select verifier('M', 'côté David plus en imprévu : Kevin y redevient simplement prévu, sans push',
  statut_fiche(:'kd') = 'null' and g_push(:n0, :'K') = '' and g_push(:n0, :'D') = '');

-- ===================================================================
-- S. Déclaration d'imprévu, état des rappels, droits
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k') \gset
select verifier('S', 'une demande : cherche', ia_etat(:'p', 'initiateur') = 'cherche');
select g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'true') \gset
select verifier('S', 'acceptée : remplace (la déclaration reste)', ia_etat(:'p', 'initiateur') = 'remplace' and ia_declare(:'p', 'initiateur'));
select g_rpc(:'K', 'se_desister_du_remplacement', :'k') \gset
select verifier('S', 'désistement : cherche de nouveau', ia_etat(:'p', 'initiateur') = 'cherche');

-- Ancienne action « Annuler la demande » (jusqu'au lot 3) : même règle qu'avant.
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k') \gset
select g_rpc(:'E', 'annuler_demande_remplacement', :'k') \gset
select verifier('S', 'annuler sa seule demande : plus d''imprévu (comme avant)',
  ia_etat(:'p', 'initiateur') = 'normal' and not ia_declare(:'p', 'initiateur'));
select g_rpc(:'E', 'envoyer_demande_remplacement', :'c') \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'c', 'false') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'k') \gset
select g_rpc(:'E', 'annuler_demande_remplacement', :'k') \gset
select verifier('S', 'annuler une demande après un refus : toujours en imprévu (comme avant)',
  ia_etat(:'p', 'initiateur') = 'cherche');
select verifier('S', 'destination au clic d''un rappel : « Un imprévu ? »',
  en_tant_que(:'E', format('select set_config(%L, destination_rappel(%L), false)', 'qa.dest', :'p')) = 'OK'
  and current_setting('qa.dest') = 'imprevu');

select verifier('S', 'tables internes illisibles par l''app',
  en_tant_que(:'E', 'select count(*) from imprevus_declares') like '%permission denied%'
  and en_tant_que(:'D', 'select count(*) from imprevus_declares') like '%permission denied%'
  and en_tant_que(:'E', 'insert into imprevus_declares (pacte_id, cote) values (gen_random_uuid(), ''initiateur'')') like '%permission denied%');
select verifier('S', 'outils internes non exécutables par l''app',
  not has_function_privilege('authenticated', 'public.pousser_personne(uuid, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.pousser_titulaire(uuid, text, text, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.prenom_titulaire_de(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.etat_cote_titulaire(uuid, text)', 'execute'));
select verifier('S', 'nouvelles actions : authenticated oui, anon non',
  has_function_privilege('authenticated', 'public.je_peux_finalement_venir(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.marquer_message_renvoye(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.je_peux_finalement_venir(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.marquer_message_renvoye(uuid)', 'execute'));
select en_tant_que(:'E', format(
    'insert into remplacants (pacte_id, cote, prenom, nom, telephone, email, demande_statut, message_a_renvoyer) values (%L, %L, %L, %L, %L, %L, %L, true)',
    :'p', 'initiateur', 'Forge', 'X', '0711000099', '', 'envoyee')) as r \gset
select verifier('S', 'INSERT forgé « en attente + message à renvoyer » neutralisé',
  :'r' = 'OK' and (select statut_fiche(id) || '/' || message_a_renvoyer from remplacants where pacte_id = :'p' and prenom = 'Forge') = 'null/false', :'r');

-- Rejouer la migration ne recrée jamais une déclaration effacée.
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ia_envoyer(:'E', array[:'k', :'c']::uuid[]) \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'k', 'false') \gset
select g_rpc(:'E', 'je_peux_finalement_venir', :'p') \gset
\ir ../../../supabase/migrations/20261012000000_imprevu_etats_et_actions.sql
-- D-027 lot 2 redéfinit ensuite l'annulation et les accès, puis l'échéance H-3
-- les actions : état réel rétabli.
\o /dev/null
\ir ../../../supabase/migrations/20261015000000_annulation_et_conversations.sql
\ir ../../../supabase/migrations/20261020000000_echeance_h3.sql
\o
select verifier('S', 'migration rejouée : le retour d''Eliot reste acquis (pas de déclaration recréée)',
  not ia_declare(:'p', 'initiateur') and ia_etat(:'p', 'initiateur') = 'normal');

-- Remplissage initial (production) : uniquement à la création de la table.
select nouveau_swend() as pa \gset
select ajouter_fiche(:'E', :'pa', 'initiateur', 'Kevin', '0600000003') as ka \gset
select ajouter_fiche(:'D', :'pa', 'destinataire', 'Camille', '0600000004') as ca \gset
select ajouter_fiche(:'D', :'pa', 'destinataire', 'Thomas', '0600000005') as ta \gset
update remplacants set demande_statut = 'refusee' where id = :'ka';
update remplacants set demande_statut = 'acceptee', selectionne = true where id = :'ca';
select nouveau_swend() as pb \gset
select ajouter_fiche(:'E', :'pb', 'initiateur', 'Kevin', '0600000003') as kb \gset
select g_swend(now() + interval '2 days') as pc \gset
select ajouter_fiche(:'E', :'pc', 'initiateur', 'Kevin', '0600000003') as kc \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'kc') \gset
select en_tant_que(:'E', format('select annuler_swend(%L)', :'pc')) \gset
create temp table ia_avant as select pacte_id, cote from imprevus_declares;
drop table imprevus_declares;
\ir ../../../supabase/migrations/20261012000000_imprevu_etats_et_actions.sql
-- D-027 lot 2 redéfinit ensuite l'annulation et les accès, puis l'échéance H-3
-- les actions : état réel rétabli.
\o /dev/null
\ir ../../../supabase/migrations/20261015000000_annulation_et_conversations.sql
\ir ../../../supabase/migrations/20261020000000_echeance_h3.sql
\o
select verifier('S', 'remplissage : côté avec un refus → déclaré ; côté remplacé → déclaré',
  ia_declare(:'pa', 'initiateur') and ia_declare(:'pa', 'destinataire'));
select verifier('S', 'remplissage : côté sans demande → rien ; Swend annulé → rien',
  not ia_declare(:'pb', 'initiateur') and not ia_declare(:'pc', 'initiateur'));
select verifier('S', 'remplissage : tables internes recréées sans accès pour l''app',
  en_tant_que(:'E', 'select count(*) from imprevus_declares') like '%permission denied%');
-- Les autres suites n'en dépendent pas, mais on rétablit l'état réel.
truncate imprevus_declares;
insert into imprevus_declares (pacte_id, cote) select pacte_id, cote from ia_avant on conflict do nothing;

-- Swends de cette suite datés dans le passé : traités par le moteur du gel
-- ici, pour ne laisser aucune clôture (ni push) aux suites suivantes.
select figer_swends_passes() \gset

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
