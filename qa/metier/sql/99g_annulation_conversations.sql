-- « En cas d'imprévu », lot 2 : annulation et conversations (D-027).
-- Utilise les outils de 10_imprevu.sql (verifier, en_tant_que,
-- compter_en_tant_que, ajouter_fiche, statut_fiche), 98_gel_a_h.sql (g_swend,
-- g_dater, g_rpc, g_ecrire, g_lire, g_codes, g_push, g_nb_push, g_n0,
-- g_acces, g_tel), 99b_chat_apres_swend.sql (cs_lire, cs_envoyer,
-- cs_participants, cs_push) et 99e_nouveau_swend.sql (nv_swend, nv_sceller,
-- nv_etat, nv_options, nv_creer, nv_participant). Swends Eliot (initiateur) /
-- David (destinataire).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;

\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set T '00000000-0000-0000-0000-00000000000b'
\set Z '00000000-0000-0000-0000-00000000000f'
\set W '00000000-0000-0000-0000-000000000077'
\set Y '00000000-0000-0000-0000-000000000078'
\set X '00000000-0000-0000-0000-000000000079'

-- ---------- outils ----------
-- plpgsql : chaque appel relit l'état réel.
create or replace function ac_chat(p uuid) returns text language plpgsql as $$
begin
  return coalesce((select nature || case when ferme_le is null then '' else ':ferme' end
                   from chats_apres_swend where pacte_id = p), 'aucun');
end $$;
create or replace function ac_ferme(p_fiche uuid) returns boolean language plpgsql as $$
begin
  return exists (select 1 from fils_imprevu_fermes where remplacant_id = p_fiche);
end $$;
create or replace function ac_annulation(p uuid) returns text language plpgsql as $$
begin
  return (select statut || '|' || coalesce(annule_motif, 'null') || '|'
                 || coalesce((select prenom from profiles where id = annule_par), 'null')
                 || '|' || case when annule_le is null then 'null' else 'date' end
          from pactes where id = p);
end $$;
-- Résumé d'une conversation d'imprévu vue par une personne : accès à la
-- fiche (0/1), écriture (OK ou refus), numéro obtenu (vide si aucun).
create or replace function ac_vue(p_user uuid, p_fiche uuid) returns text language plpgsql as $$
declare v_acces int; v_ecrit text;
begin
  v_acces := compter_en_tant_que(p_user, format('select count(*)::int from remplacants where id = %L', p_fiche));
  v_ecrit := case when g_ecrire(p_user, p_fiche, 'Test') = 'OK' then 'ecrit' else 'lecture_seule' end;
  return v_acces || '|' || v_ecrit || '|' || coalesce(nullif(g_tel(p_user, 'telephone_titulaire_accessible', p_fiche), ''), '-');
end $$;

-- Les Swends passés laissés par les autres fichiers de test sont traités
-- d'abord : la suite ne compte que ses propres Swends.
select figer_swends_passes();

-- ===================================================================
-- A. Titulaire remplacé : il ne peut plus annuler ; l'autre titulaire le peut
-- ===================================================================
select g_swend(now() + interval '2 days') as pa \gset
select ajouter_fiche(:'E', :'pa', 'initiateur', 'Kevin', '0600000003') as ka \gset
select ajouter_fiche(:'D', :'pa', 'destinataire', 'Camille', '0600000004') as ca \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ka') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'ka', 'true') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'ca') \gset
select g_n0() as n0 \gset
select verifier('A', 'Eliot (remplacé par Kevin) ne peut plus annuler → remplacement_accepte',
  g_rpc(:'E', 'annuler_swend', :'pa') like '%remplacement_accepte%');
select verifier('A', 'refus : rien ne bouge (Swend maintenu, demande de Camille en attente, aucun chat, aucune push)',
  ac_annulation(:'pa') = 'confirme|null|null|null' and statut_fiche(:'ca') = 'envoyee'
  and ac_chat(:'pa') = 'aucun' and g_nb_push(:n0) = 0, ac_annulation(:'pa'));
select verifier('A', 'Kevin (remplaçant) ne peut pas annuler',
  g_rpc(:'K', 'annuler_swend', :'pa') like '%non_autorise%');
select verifier('A', 'David (pas remplacé) peut annuler', g_rpc(:'D', 'annuler_swend', :'pa') = 'OK');
select verifier('A', 'annulation : motif titulaire, auteur David, date posée',
  ac_annulation(:'pa') = 'annule|titulaire|David|date', ac_annulation(:'pa'));
select verifier('A', 'push Eliot : « David ne pourra finalement pas être là. »',
  g_push(:n0, :'E') = 'Le Swend est annulé|David ne pourra finalement pas être là.', g_push(:n0, :'E'));
select verifier('A', 'push Kevin (sélectionné) : « …prendre la place d’Eliot. »',
  g_push(:n0, :'K') = 'Le Swend est annulé|Tu n’auras finalement pas besoin de prendre la place d’Eliot.', g_push(:n0, :'K'));
select verifier('A', 'push Camille (demande en attente close) : « Tu n’as plus besoin de répondre. »',
  g_push(:n0, :'C') = 'Le Swend est annulé|Tu n’as plus besoin de répondre.' and statut_fiche(:'ca') = 'cloturee',
  g_push(:n0, :'C'));
select verifier('A', 'rien pour David (auteur) ; 3 push en tout, aucune push d''ouverture de chat',
  g_push(:n0, :'D') = '' and g_nb_push(:n0) = 3, g_nb_push(:n0)::text);

-- ===================================================================
-- B. Chat d'annulation : immédiat, titulaires seulement, sans push
-- ===================================================================
select id as cha from chats_apres_swend where pacte_id = :'pa' \gset
select verifier('B', 'chat d''annulation ouvert avec l''annulation (nature annulation, ouvert maintenant)',
  ac_chat(:'pa') = 'annulation'
  and (select ouvert_le is not null and ouvre_le <= now() from chats_apres_swend where id = :'cha'));
select verifier('B', 'participants : Eliot et David seulement, jamais un remplaçant ni une personne sollicitée',
  cs_participants(:'pa') = 'destinataire:David,initiateur:Eliot', cs_participants(:'pa'));
select verifier('B', 'app publiée : masqué de mes_chats_apres_swend (Eliot et David)',
  cs_lire(:'E', format('select count(*)::text from mes_chats_apres_swend() where chat_id = %L', :'cha')) = '0'
  and cs_lire(:'D', format('select count(*)::text from mes_chats_apres_swend() where chat_id = %L', :'cha')) = '0');
select verifier('B', 'app du lot 3 : visible dans mes_chats_swend, nature annulation, pour Eliot et David',
  cs_lire(:'E', format('select nature from mes_chats_swend() where chat_id = %L', :'cha')) = 'annulation'
  and cs_lire(:'D', format('select nature from mes_chats_swend() where chat_id = %L', :'cha')) = 'annulation');
select verifier('B', 'Kevin et Camille ne voient ni le chat, ni ses participants, ni ses messages',
  cs_lire(:'K', format('select count(*)::text from chats_apres_swend where id = %L', :'cha')) = '0'
  and cs_lire(:'K', format('select count(*)::text from mes_chats_swend() where chat_id = %L', :'cha')) = '0'
  and cs_lire(:'K', format('select count(*)::text from participants_chat_apres_swend where chat_id = %L', :'cha')) = '0'
  and cs_lire(:'C', format('select count(*)::text from chats_apres_swend where id = %L', :'cha')) = '0'
  and cs_lire(:'C', format('select count(*)::text from mes_chats_swend() where chat_id = %L', :'cha')) = '0');
select g_n0() as n0 \gset
select verifier('B', 'Eliot écrit à David dans le chat d''annulation', cs_envoyer(:'E', :'cha', 'On remet ça ?') = 'OK');
select verifier('B', 'David reçoit seulement la push de message habituelle (sans contenu)',
  g_push(:n0, :'D') like 'Eliot vous a écrit|%' and g_push(:n0, :'D') not like '%remet%' and g_nb_push(:n0) = 1,
  g_push(:n0, :'D'));
select verifier('B', 'Kevin ne peut pas écrire dans ce chat',
  cs_envoyer(:'K', :'cha', 'Coucou') like '%non_autorise%');
select verifier('B', 'Kevin et Camille ne lisent aucun message de ce chat',
  cs_lire(:'K', format('select count(*)::text from messages_apres_swend where chat_id = %L', :'cha')) = '0'
  and cs_lire(:'C', format('select count(*)::text from messages_apres_swend where chat_id = %L', :'cha')) = '0');

-- ===================================================================
-- C. Jamais de chat après le Swend ensuite (ni pour un Swend annulé sans
--    chat d'annulation)
-- ===================================================================
select g_dater(:'pa', now() - interval '4 hours');
select figer_swends_passes() \gset
select cs_n0() as n0 \gset
select ouvrir_chats_apres_swend(now() + interval '1 day') \gset
select verifier('C', 'après l''heure du Swend : toujours un seul chat, celui d''annulation, ouvert',
  (select count(*) from chats_apres_swend where pacte_id = :'pa') = 1 and ac_chat(:'pa') = 'annulation');
select verifier('C', 'aucune push « Alors, ce Swend ? » pour ce Swend', cs_push(:'n0', :'pa') = '', cs_push(:'n0', :'pa'));
select verifier('C', 'mes_chats_apres_swend reste sans chat pour ce Swend (Eliot, David, Kevin)',
  cs_lire(:'E', format('select count(*)::text from mes_chats_apres_swend() where pacte_id = %L', :'pa')) = '0'
  and cs_lire(:'D', format('select count(*)::text from mes_chats_apres_swend() where pacte_id = %L', :'pa')) = '0'
  and cs_lire(:'K', format('select count(*)::text from mes_chats_apres_swend() where pacte_id = %L', :'pa')) = '0');
select verifier('C', 'le chat d''annulation reste ouvert à l''écriture après l''heure',
  cs_envoyer(:'D', :'cha', 'Oui, avec plaisir') = 'OK');
-- Double remplacement puis heure passée : idem.
select g_swend(now() + interval '2 days') as pc \gset
select ajouter_fiche(:'E', :'pc', 'initiateur', 'Kevin', '0600000003') as kc \gset
select ajouter_fiche(:'D', :'pc', 'destinataire', 'Camille', '0600000004') as cc \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'kc') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'cc') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'kc', 'true') \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'cc', 'true') \gset
select g_dater(:'pc', now() - interval '4 hours');
select figer_swends_passes() \gset
select cs_n0() as n0 \gset
select ouvrir_chats_apres_swend(now() + interval '1 day') \gset
select verifier('C', 'double remplacement passé : seulement le chat d''annulation, aucun « Alors, ce Swend ? »',
  (select count(*) from chats_apres_swend where pacte_id = :'pc') = 1 and ac_chat(:'pc') = 'annulation'
  and cs_push(:'n0', :'pc') = '' and cs_participants(:'pc') = 'destinataire:David,initiateur:Eliot',
  ac_chat(:'pc') || ' ' || cs_participants(:'pc'));

-- ===================================================================
-- D. Double remplacement : notifications D-027, une par personne
-- ===================================================================
select g_swend(now() + interval '2 days') as pd \gset
select ajouter_fiche(:'E', :'pd', 'initiateur', 'Kevin', '0600000003') as kd \gset
select ajouter_fiche(:'D', :'pd', 'destinataire', 'Camille', '0600000004') as cd \gset
select ajouter_fiche(:'D', :'pd', 'destinataire', 'Walter', '0600000007') as wd \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'kd') \gset
select g_rpc(:'K', 'repondre_demande_remplacement', :'kd', 'true') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'cd') \gset
select g_rpc(:'D', 'envoyer_demande_remplacement', :'wd') \gset
select g_n0() as n0 \gset
select verifier('D', 'Camille accepte : les deux côtés sont remplacés', g_rpc(:'C', 'repondre_demande_remplacement', :'cd', 'true') = 'OK');
select verifier('D', 'Swend annulé par la base : motif double_remplacement, sans auteur',
  ac_annulation(:'pd') = 'annuleDoubleAbsence|double_remplacement|null|date', ac_annulation(:'pd'));
select verifier('D', 'push Eliot : « Ni toi ni David ne pourrez finalement être là. »',
  g_push(:n0, :'E') = 'Le Swend est annulé.|Ni toi ni David ne pourrez finalement être là.', g_push(:n0, :'E'));
select verifier('D', 'push David : « Ni toi ni Eliot ne pourrez finalement être là. »',
  g_push(:n0, :'D') = 'Le Swend est annulé.|Ni toi ni Eliot ne pourrez finalement être là.', g_push(:n0, :'D'));
select verifier('D', 'push Kevin : « …prendre la place d’Eliot. »',
  g_push(:n0, :'K') = 'Le Swend est annulé|Tu n’auras finalement pas besoin de prendre la place d’Eliot.', g_push(:n0, :'K'));
select verifier('D', 'push Camille (sa propre acceptation) : seulement « …prendre la place de David. »',
  g_push(:n0, :'C') = 'Le Swend est annulé|Tu n’auras finalement pas besoin de prendre la place de David.', g_push(:n0, :'C'));
select verifier('D', 'push Walter (demande en attente close, second côté) : « Tu n’as plus besoin de répondre. »',
  g_push(:n0, :'W') = 'Le Swend est annulé|Tu n’as plus besoin de répondre.' and statut_fiche(:'wd') = 'cloturee',
  g_push(:n0, :'W'));
select verifier('D', 'exactement 5 push : une par personne, aucune d''ouverture de chat',
  g_nb_push(:n0) = 5, g_nb_push(:n0)::text);
select verifier('D', 'chat d''annulation entre Eliot et David seulement',
  ac_chat(:'pd') = 'annulation' and cs_participants(:'pd') = 'destinataire:David,initiateur:Eliot');
select verifier('D', 'conversations des sélectionnés et de Walter (sollicité) conservées et écrivables ; numéros D-024',
  ac_vue(:'K', :'kd') = '1|ecrit|0600000001' and ac_vue(:'C', :'cd') = '1|ecrit|0600000002'
  and ac_vue(:'W', :'wd') = '1|ecrit|-',
  ac_vue(:'K', :'kd') || ' ' || ac_vue(:'C', :'cd') || ' ' || ac_vue(:'W', :'wd'));
select verifier('D', 'Kevin ne voit pas Camille ni Walter ; Camille ne voit pas Kevin',
  compter_en_tant_que(:'K', format('select count(*)::int from remplacants where pacte_id = %L', :'pd')) = 1
  and compter_en_tant_que(:'C', format('select count(*)::int from remplacants where pacte_id = %L', :'pd')) = 1
  and compter_en_tant_que(:'W', format('select count(*)::int from remplacants where pacte_id = %L', :'pd')) = 1);

-- ===================================================================
-- E. Conversations après annulation : qui garde quoi (accès, écriture,
--    numéro D-024 inchangé)
-- ===================================================================
select g_swend(now() + interval '2 days') as pe \gset
select ajouter_fiche(:'E', :'pe', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'E', :'pe', 'initiateur', 'Camille', '0600000004') as ce \gset
select ajouter_fiche(:'E', :'pe', 'initiateur', 'Yann', '0600000008') as ye \gset
select ajouter_fiche(:'E', :'pe', 'initiateur', 'Thomas', '0600000005') as te \gset
select ajouter_fiche(:'E', :'pe', 'initiateur', 'Xavier', '0600000009') as xe \gset
select ajouter_fiche(:'E', :'pe', 'initiateur', 'Zoé', '0600000006') as ze \gset
select ajouter_fiche(:'D', :'pe', 'destinataire', 'Walter', '0600000007') as we \gset
-- Côté Eliot : Yann accepte puis se désiste ; Camille refuse ; Zoé
-- sollicitée, demande annulée, puis retirée ; Thomas seulement prévu mais a
-- écrit ; Xavier seulement prévu, fil vierge ; Kevin en attente.
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ye') \gset
select g_rpc(:'Y', 'repondre_demande_remplacement', :'ye', 'true') \gset
select g_rpc(:'Y', 'se_desister_du_remplacement', :'ye') as r_desist \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ce') \gset
select g_rpc(:'C', 'repondre_demande_remplacement', :'ce', 'false') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ze') \gset
select g_rpc(:'E', 'annuler_demande_remplacement', :'ze') \gset
select g_rpc(:'E', 'retirer_remplacant', :'ze') \gset
select g_ecrire(:'T', :'te', 'Je serai dispo si besoin') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'ke') \gset
-- Côté David : Walter sélectionné (David, remplacé, ne peut plus annuler ;
-- Eliot n'a personne de sélectionné).
select g_rpc(:'D', 'envoyer_demande_remplacement', :'we') \gset
select g_rpc(:'W', 'repondre_demande_remplacement', :'we', 'true') \gset
select verifier('E', 'préparation : Yann désisté, Camille a refusé, Zoé retirée, Kevin en attente, Walter sélectionné',
  :'r_desist' = 'OK' and statut_fiche(:'ce') = 'refusee' and statut_fiche(:'ke') = 'envoyee'
  and statut_fiche(:'we') = 'acceptee+sel'
  and (select retire_le is not null from remplacants where id = :'ze'),
  :'r_desist' || ' ' || statut_fiche(:'ye') || ' ' || statut_fiche(:'ce'));
select verifier('E', 'David (remplacé par Walter) ne peut plus annuler',
  g_rpc(:'D', 'annuler_swend', :'pe') like '%remplacement_accepte%');
select verifier('E', 'Eliot annule', g_rpc(:'E', 'annuler_swend', :'pe') = 'OK');
select verifier('E', 'Kevin (demande en attente close) : conversation lisible et écrivable, aucun numéro',
  ac_vue(:'K', :'ke') = '1|ecrit|-', ac_vue(:'K', :'ke'));
select verifier('E', 'Camille (a refusé) : conversation lisible et écrivable, aucun numéro',
  ac_vue(:'C', :'ce') = '1|ecrit|-', ac_vue(:'C', :'ce'));
select verifier('E', 'Yann (s''est désisté) : conversation lisible et écrivable, aucun numéro',
  ac_vue(:'Y', :'ye') = '1|ecrit|-', ac_vue(:'Y', :'ye'));
select verifier('E', 'P1 : Thomas (seulement prévu, messages échangés, aucune demande) : lisible et écrivable, aucun numéro',
  ac_vue(:'T', :'te') = '1|ecrit|-', ac_vue(:'T', :'te'));
select verifier('E', 'Walter (sélectionné côté David) : lisible, écrivable, garde le numéro de David (D-024)',
  ac_vue(:'W', :'we') = '1|ecrit|0600000002', ac_vue(:'W', :'we'));
select verifier('E', 'P1 : Xavier (seulement prévu, ni demande ni échange) : aucun accès',
  ac_vue(:'X', :'xe') = '0|lecture_seule|-'
  and compter_en_tant_que(:'X', format('select count(*)::int from pactes where id = %L', :'pe')) = 0,
  ac_vue(:'X', :'xe'));
select verifier('E', 'Zoé (retirée avant l''annulation) : rien, pas de retour d''accès',
  ac_vue(:'Z', :'ze') = '0|lecture_seule|-'
  and compter_en_tant_que(:'Z', format('select count(*)::int from pactes where id = %L', :'pe')) = 0,
  ac_vue(:'Z', :'ze'));
select verifier('E', 'Eliot écrit dans chaque conversation conservée ; pas dans le fil vierge de Xavier',
  g_ecrire(:'E', :'ke', 'Merci quand même') = 'OK' and g_ecrire(:'E', :'ce', 'Pas de souci') = 'OK'
  and g_ecrire(:'E', :'ye', 'Merci') = 'OK' and g_ecrire(:'E', :'te', 'Merci') = 'OK'
  and g_ecrire(:'E', :'xe', 'Coucou') like '%row-level security%');
select verifier('E', 'aucune nouvelle conversation : Eliot ne peut plus solliciter Xavier (swend_inactif)',
  g_rpc(:'E', 'envoyer_demande_remplacement', :'xe') like '%swend_inactif%');
select verifier('E', 'Kevin ne peut plus accepter une demande close',
  g_rpc(:'K', 'repondre_demande_remplacement', :'ke', 'true') <> 'OK' and statut_fiche(:'ke') = 'cloturee');
select verifier('E', 'retirer une fiche d''un Swend annulé → swend_inactif (rien ne coupe une conversation)',
  g_rpc(:'E', 'retirer_remplacant', :'xe') like '%swend_inactif%'
  and g_rpc(:'E', 'retirer_remplacant', :'ce') like '%swend_inactif%');
select verifier('E', 'David ne découvre aucune coulisse d''Eliot (fiches, messages, événements)',
  compter_en_tant_que(:'D', format('select count(*)::int from remplacants where pacte_id = %L and cote = %L', :'pe', 'initiateur')) = 0
  and compter_en_tant_que(:'D', format('select count(*)::int from messages where remplacant_id in (%L, %L, %L, %L)', :'ke', :'ce', :'ye', :'te')) = 0
  and compter_en_tant_que(:'D', format('select count(*)::int from evenements_fil where remplacant_id in (%L, %L, %L, %L)', :'ke', :'ce', :'ye', :'te')) = 0);
select verifier('E', 'Eliot ne lit pas la conversation de David avec Walter',
  g_lire(:'E', :'we') = 0
  and compter_en_tant_que(:'E', format('select count(*)::int from remplacants where id = %L', :'we')) = 0);
select verifier('E', 'les personnes de confiance ne se découvrent pas entre elles',
  compter_en_tant_que(:'K', format('select count(*)::int from remplacants where pacte_id = %L', :'pe')) = 1
  and compter_en_tant_que(:'C', format('select count(*)::int from remplacants where pacte_id = %L', :'pe')) = 1
  and compter_en_tant_que(:'T', format('select count(*)::int from remplacants where pacte_id = %L', :'pe')) = 1
  and compter_en_tant_que(:'W', format('select count(*)::int from remplacants where pacte_id = %L', :'pe')) = 1);
select verifier('E', 'le chat d''annulation ne contient que les titulaires',
  cs_participants(:'pe') = 'destinataire:David,initiateur:Eliot');

-- ===================================================================
-- F. Fermeture paire par paire au scellement d'un nouveau Swend
-- ===================================================================
select g_n0() as n0 \gset
select nv_swend(:'K', :'Z', now() + interval '20 days') as s_kz \gset
select verifier('F', 'Kevin et Zoé scellent : aucune conversation fermée',
  not ac_ferme(:'ke') and not ac_ferme(:'ze') and ac_vue(:'K', :'ke') = '1|ecrit|-');
select nv_swend(:'E', :'W', now() + interval '21 days') as s_ew \gset
select verifier('F', 'Eliot et Walter scellent : la conversation de Walter (avec David) reste ouverte',
  not ac_ferme(:'we') and ac_vue(:'W', :'we') = '1|ecrit|0600000002');
select nv_swend(:'E', :'K', now() + interval '22 days') as s_ek \gset
select verifier('F', 'Eliot et Kevin scellent : la conversation Eliot–Kevin est fermée',
  ac_ferme(:'ke') and (select nouveau_pacte_id from fils_imprevu_fermes where remplacant_id = :'ke') = :'s_ek'::uuid);
select verifier('F', 'fermée : lisible par Eliot et Kevin, plus personne n''y écrit',
  g_lire(:'K', :'ke') >= 2 and g_lire(:'E', :'ke') >= 2
  and g_ecrire(:'K', :'ke', 'x') like '%row-level security%' and g_ecrire(:'E', :'ke', 'x') like '%row-level security%');
select verifier('F', 'un événement « fil_ferme », visible dans la conversation',
  g_codes(:'ke') like '%fil_ferme' and (select count(*) from evenements_fil where remplacant_id = :'ke' and code = 'fil_ferme') = 1
  and compter_en_tant_que(:'K', format('select count(*)::int from evenements_fil where remplacant_id = %L and code = %L', :'ke', 'fil_ferme')) = 1);
select verifier('F', 'les autres conversations du même Swend restent écrivables (Camille, Yann, Thomas)',
  not ac_ferme(:'ce') and not ac_ferme(:'ye') and not ac_ferme(:'te')
  and g_ecrire(:'C', :'ce', 'x') = 'OK' and g_ecrire(:'Y', :'ye', 'x') = 'OK' and g_ecrire(:'T', :'te', 'x') = 'OK');
select verifier('F', 'aucune push liée aux fermetures', g_nb_push(:n0) = 0, g_nb_push(:n0)::text);
select nv_swend(:'K', :'E', now() + interval '40 days') as s_ke2 \gset
select verifier('F', 'nouveau scellement Kevin–Eliot : pas de seconde fermeture ni d''événement en double',
  (select count(*) from evenements_fil where remplacant_id = :'ke' and code = 'fil_ferme') = 1
  and (select nouveau_pacte_id from fils_imprevu_fermes where remplacant_id = :'ke') = :'s_ek'::uuid);
select nv_swend(:'E', :'D', now() + interval '23 days') as s_ed \gset
select verifier('F', 'Eliot et David scellent : chat d''annulation fermé (D-023c), aucune conversation d''imprévu fermée',
  ac_chat(:'pe') = 'annulation:ferme' and nv_etat((select id from chats_apres_swend where pacte_id = :'pe')) = 'ferme:nouveau_swend|systeme=1'
  and not ac_ferme(:'ce') and not ac_ferme(:'ye') and not ac_ferme(:'te') and not ac_ferme(:'we'),
  ac_chat(:'pe'));
select nv_swend(:'W', :'D', now() + interval '24 days') as s_wd \gset
select verifier('F', 'David et Walter scellent : la conversation David–Walter est fermée',
  ac_ferme(:'we') and g_ecrire(:'W', :'we', 'x') like '%row-level security%' and g_ecrire(:'D', :'we', 'x') like '%row-level security%');
select verifier('F', 'D-024 inchangé après fermeture : Walter (sélectionné) garde le numéro de David',
  g_tel(:'W', 'telephone_titulaire_accessible', :'we') = '0600000002');
select nv_swend(:'C', :'E', now() + interval '25 days', 'enAttenteChoixDateDestinataire') as s_ce \gset
select verifier('F', 'une invitation non scellée (Camille → Eliot) ne ferme rien', not ac_ferme(:'ce'));
select nv_sceller(:'s_ce');
select verifier('F', 'son scellement ferme la conversation Eliot–Camille', ac_ferme(:'ce'));

-- ===================================================================
-- G. P2 (validée le 15/10) : un nouveau scellement entre les mêmes personnes
--    empêche l'annulation de l'ancien Swend de rouvrir leur conversation.
--    Scellement survenu avant l'annulation : même issue que s'il venait
--    après ; un Swend plus ancien entre les mêmes personnes ne ferme rien
-- ===================================================================
select nv_swend(:'E', :'Y', now() - interval '30 days') as s_ancien \gset
select g_swend(now() + interval '2 days') as pg \gset
select ajouter_fiche(:'E', :'pg', 'initiateur', 'Yann', '0600000008') as yg \gset
select ajouter_fiche(:'E', :'pg', 'initiateur', 'Thomas', '0600000005') as tg \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'yg') \gset
select g_rpc(:'E', 'envoyer_demande_remplacement', :'tg') \gset
select nv_swend(:'T', :'E', now() + interval '30 days') as s_te \gset
select verifier('G', 'Swend en cours : la conversation Eliot–Thomas reste ouverte (règle D-023a)',
  not ac_ferme(:'tg') and g_ecrire(:'T', :'tg', 'Dispo') = 'OK');
select verifier('G', 'Eliot annule', g_rpc(:'E', 'annuler_swend', :'pg') = 'OK');
select verifier('G', 'P2 : Thomas et Eliot avaient scellé depuis : conversation fermée dès l''annulation, lisible',
  ac_ferme(:'tg') and (select nouveau_pacte_id from fils_imprevu_fermes where remplacant_id = :'tg') = :'s_te'::uuid
  and g_codes(:'tg') like '%fil_ferme' and g_ecrire(:'T', :'tg', 'x') like '%row-level security%'
  and g_lire(:'T', :'tg') = 1 and g_lire(:'E', :'tg') = 1);
select verifier('G', 'Yann : Swend plus ancien avec Eliot, rien depuis → conversation ouverte',
  not ac_ferme(:'yg') and ac_vue(:'Y', :'yg') = '1|ecrit|-', ac_vue(:'Y', :'yg'));

-- ===================================================================
-- H. Chat d'annulation et « Faire un nouveau Swend » (D-023c)
-- ===================================================================
-- Deux comptes propres (Eliot et David ont d'autres Swends en cours dans
-- cette base de test).
\set O '00000000-0000-0000-0000-000000000501'
\set R '00000000-0000-0000-0000-000000000502'
insert into profiles (id, prenom, nom, telephone) values
  (:'O', 'Ophélie', 'O', '0615000001'), (:'R', 'Rémi', 'R', '0615000002') on conflict do nothing;
select nv_swend(:'O', :'R', now() + interval '2 days') as ph \gset
select g_rpc(:'R', 'annuler_swend', :'ph') \gset
select id as chh from chats_apres_swend where pacte_id = :'ph' \gset
select verifier('H', 'Rémi annule : chat d''annulation Ophélie–Rémi', ac_chat(:'ph') = 'annulation'
  and cs_participants(:'ph') = 'destinataire:Rémi,initiateur:Ophélie', cs_participants(:'ph'));
select verifier('H', 'chat d''annulation : chacun peut proposer un nouveau Swend à l''autre',
  nv_options(:'O', :'chh') = 'Rémi:libre' and nv_options(:'R', :'chh') = 'Ophélie:libre',
  nv_options(:'O', :'chh') || ' / ' || nv_options(:'R', :'chh'));
select nv_creer(:'O', :'chh', nv_participant(:'chh', :'R'), now() + interval '30 days') as nouveau \gset
select verifier('H', 'Ophélie crée un nouveau Swend depuis le chat d''annulation ; le chat reste ouvert',
  :'nouveau' ~ '^[0-9a-f-]{36}$' and ac_chat(:'ph') = 'annulation', :'nouveau');
select verifier('H', 'Swend déjà en cours entre eux : option signalée',
  nv_options(:'O', :'chh') = 'Rémi:en_cours');
select nv_sceller(:'nouveau');
select verifier('H', 'scellé : chat d''annulation fermé, un message système, écriture refusée',
  nv_etat(:'chh') = 'ferme:nouveau_swend|systeme=1' and cs_envoyer(:'O', :'chh', 'x') like '%chat_ferme%',
  nv_etat(:'chh'));

-- ===================================================================
-- I. Droits et confidentialité des nouveaux objets
-- ===================================================================
select verifier('I', 'fils_imprevu_fermes : aucun accès de l''app',
  not has_table_privilege('authenticated', 'public.fils_imprevu_fermes', 'select')
  and not has_table_privilege('anon', 'public.fils_imprevu_fermes', 'select')
  and not has_table_privilege('authenticated', 'public.fils_imprevu_fermes', 'insert'));
select verifier('I', 'fonctions internes non exécutables par l''app',
  not has_function_privilege('authenticated', 'public.appliquer_annulation(uuid, text, text, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.ouvrir_chat_annulation(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.fil_conserve_apres_annulation(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.fiche_acces_d023a(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.cle_paire_fil_imprevu(uuid, uuid)', 'execute'));
select verifier('I', 'mes_chats_swend : authenticated seulement',
  has_function_privilege('authenticated', 'public.mes_chats_swend()', 'execute')
  and not has_function_privilege('anon', 'public.mes_chats_swend()', 'execute'));
select verifier('I', 'l''app ne peut ni créer un chat ni changer sa nature',
  en_tant_que(:'E', format('update chats_apres_swend set nature = %L where id = %L', 'apres_swend', :'cha')) <> 'OK'
  and (select nature from chats_apres_swend where id = :'cha') = 'annulation');
select verifier('I', 'l''app ne peut pas poser le motif d''annulation',
  en_tant_que(:'E', format('update pactes set annule_motif = %L where id = %L', 'operationnelle', :'pa')) <> 'OK'
  and (select annule_motif from pactes where id = :'pa') = 'titulaire');

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
