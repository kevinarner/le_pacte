-- Scénarios A–H exécutés réellement contre la migration v2.
-- Chaque action est faite "en tant que" l'utilisateur concerné (rôle
-- authenticated + auth.uid() simulé), exactement comme l'app via
-- PostgREST : RLS et GRANT s'appliquent.
\set ON_ERROR_STOP 1
\pset footer off

-- ---------- outils de test (exécutés en postgres) ----------
create table if not exists test_resultats (id serial, scenario text, verif text, ok boolean, detail text);
truncate test_resultats;

create or replace function verifier(p_scenario text, p_verif text, p_ok boolean, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into test_resultats (scenario, verif, ok, detail) values (p_scenario, p_verif, p_ok, p_detail);
end $$;

-- Exécute une commande en tant qu'un utilisateur et renvoie le message
-- d'erreur éventuel ('OK' sinon). Le changement de rôle est local à
-- l'appel.
create or replace function en_tant_que(p_user uuid, p_sql text) returns text
language plpgsql as $$
declare v_res text := 'OK';
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql;
  exception when others then
    v_res := sqlerrm;
  end;
  execute 'reset role';
  return v_res;
end $$;

-- Lecture en tant qu'un utilisateur (RLS appliquée) : renvoie un entier.
create or replace function compter_en_tant_que(p_user uuid, p_sql text) returns int
language plpgsql as $$
declare v int;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  return v;
end $$;

create or replace function statut_fiche(p_id uuid) returns text language sql as $$
  select coalesce(demande_statut, 'null') || case when selectionne then '+sel' else '' end
  from remplacants where id = p_id
$$;

-- Personnes
insert into profiles values
 ('00000000-0000-0000-0000-00000000000e', 'Eliot', 'E', '0600000001'),
 ('00000000-0000-0000-0000-00000000000d', 'David', 'D', '0600000002'),
 ('00000000-0000-0000-0000-00000000000a', 'Kevin', 'Arner', '0600000003'),
 ('00000000-0000-0000-0000-00000000000c', 'Camille', 'Martin', '0600000004'),
 ('00000000-0000-0000-0000-00000000000b', 'Thomas', 'Dupont', '0600000005'),
 ('00000000-0000-0000-0000-00000000000f', 'Zoe', 'Z', '0600000006')
on conflict do nothing;
insert into restaurants (id, nom) values ('00000000-0000-0000-0000-0000000000aa', 'Au Père Lapin') on conflict do nothing;

\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set T '00000000-0000-0000-0000-00000000000b'
\set Z '00000000-0000-0000-0000-00000000000f'

-- Crée un Swend scellé Eliot (initiateur) / David (destinataire), avec
-- des fiches insérées PAR les titulaires eux-mêmes (chemin de l'app).
create or replace function nouveau_swend() returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, date_retenue, restaurant_id, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone)
  values ('confirme', '2026-10-13 20:00+02', '00000000-0000-0000-0000-0000000000aa',
          '00000000-0000-0000-0000-00000000000e', 'Eliot E',
          '00000000-0000-0000-0000-00000000000d', 'David D', '06 00 00 00 02')
  returning id into v;
  return v;
end $$;

create or replace function ajouter_fiche(p_titulaire uuid, p_pacte uuid, p_cote text, p_prenom text, p_tel text)
returns uuid language plpgsql as $$
declare r text; v uuid;
begin
  r := en_tant_que(p_titulaire, format(
    'insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    p_pacte, p_cote, p_prenom, 'X', p_tel, ''));
  if r <> 'OK' then raise exception 'ajout impossible : %', r; end if;
  select id into v from remplacants where pacte_id = p_pacte and cote = p_cote and telephone = p_tel
  order by id desc limit 1;
  return v;
end $$;

-- ===================================================================
-- A. Eliot demande Kevin → Kevin accepte
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select verifier('A', 'fiche liée au compte de Kevin côté serveur', (select profil_id from remplacants where id = :'k') = :'K');
select count(*) as n0 from notifications_log \gset
select verifier('A', 'Eliot envoie la demande',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) = 'OK');
select verifier('A', 'Kevin est notifié', (select count(*) from notifications_log where id > :n0 and profile_id = :'K' and titre = 'On a besoin de toi') = 1);
select verifier('A', 'Kevin accepte',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) = 'OK');
select verifier('A', 'Kevin sélectionné', statut_fiche(:'k') = 'acceptee+sel', statut_fiche(:'k'));
select verifier('A', 'Swend toujours scellé', (select statut from pactes where id = :'p') = 'confirme');
select verifier('A', 'David ne voit aucune fiche côté Eliot',
  compter_en_tant_que(:'D', format('select count(*) from remplacants where pacte_id = %L', :'p')) = 0);
select verifier('A', 'David ne reçoit aucune notification', (select count(*) from notifications_log where profile_id = :'D') = 0);
select verifier('A', 'Eliot ne peut plus annuler (transfert définitif)',
  en_tant_que(:'E', format('select annuler_demande_remplacement(%L)', :'k')) like '%deja_acceptee%');
select verifier('A', 'Eliot ne peut pas retirer Kevin',
  en_tant_que(:'E', format('select retirer_remplacant(%L)', :'k')) like '%retrait_impossible%');
select verifier('A', 'Eliot ne peut pas se re-désigner par écriture directe',
  en_tant_que(:'E', format('update remplacants set selectionne = false, demande_statut = null where id = %L', :'k')) like '%permission denied%');

-- ===================================================================
-- B. Eliot demande Kevin + Camille → Camille accepte → Kevin clôturé
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'c')) as r \gset
select verifier('B', 'deux demandes en parallèle', statut_fiche(:'k') = 'envoyee' and statut_fiche(:'c') = 'envoyee');
select count(*) as n0 from notifications_log \gset
select verifier('B', 'Camille accepte',
  en_tant_que(:'C', format('select repondre_demande_remplacement(%L, true)', :'c')) = 'OK');
select verifier('B', 'Camille sélectionnée', statut_fiche(:'c') = 'acceptee+sel');
select verifier('B', 'Kevin clôturé automatiquement', statut_fiche(:'k') = 'cloturee');
select verifier('B', 'Thomas reste disponible (jamais sollicité)', statut_fiche(:'t') = 'null');
select verifier('B', 'Kevin notifié sans révéler qui',
  (select corps from notifications_log where id > :n0 and profile_id = :'K') = 'C''est bon, quelqu''un a pu prendre la place.');
select verifier('B', 'Kevin ne peut plus accepter',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) like '%place_deja_prise%');
select verifier('B', 'plus aucune demande possible (Thomas)',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'t')) like '%place_deja_prise%');
select verifier('B', 'une seule personne sélectionnée',
  (select count(*) from remplacants where pacte_id = :'p' and selectionne) = 1);

-- ===================================================================
-- C. Eliot annule une demande en attente
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select count(*) as n0 from notifications_log \gset
select verifier('C', 'Eliot annule la demande',
  en_tant_que(:'E', format('select annuler_demande_remplacement(%L)', :'k')) = 'OK');
select verifier('C', 'Kevin revient à disponible (null)', statut_fiche(:'k') = 'null');
select verifier('C', 'aucune notification à l''annulation', (select count(*) from notifications_log where id > :n0) = 0);
select verifier('C', 'Kevin ne peut plus accepter la demande annulée',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) like '%demande_non_active%');
select verifier('C', 'Kevin peut être sollicité à nouveau',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) = 'OK' and statut_fiche(:'k') = 'envoyee');
select verifier('C', 'David ne peut pas annuler une demande d''Eliot',
  en_tant_que(:'D', format('select annuler_demande_remplacement(%L)', :'k')) like '%Non autorisé%');
select verifier('C', 'Eliot ne peut pas retirer une personne en attente',
  en_tant_que(:'E', format('select retirer_remplacant(%L)', :'k')) like '%retrait_impossible%');
select verifier('C', 'écriture directe de demande_statut refusée',
  en_tant_que(:'E', format('update remplacants set demande_statut = null where id = %L', :'k')) like '%permission denied%');
select verifier('C', 'suppression directe refusée',
  en_tant_que(:'E', format('delete from remplacants where id = %L', :'k')) like '%permission denied%');
select en_tant_que(:'E', format(
    'insert into remplacants (pacte_id, cote, prenom, nom, telephone, email, selectionne, demande_statut) values (%L, %L, %L, %L, %L, %L, true, %L)',
    :'p', 'initiateur', 'Forge', 'X', '0600000099', '', 'acceptee')) as r \gset
select verifier('C', 'INSERT forgé "déjà sélectionné/acceptée" neutralisé',
  :'r' = 'OK' and (select statut_fiche(id) from remplacants where pacte_id = :'p' and prenom = 'Forge') = 'null', :'r');

-- ===================================================================
-- D. Kevin refuse
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'c')) as r \gset
select verifier('D', 'Kevin refuse',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, false)', :'k')) = 'OK');
select verifier('D', 'Kevin indisponible (refusee)', statut_fiche(:'k') = 'refusee');
select verifier('D', 'la demande à Camille reste active', statut_fiche(:'c') = 'envoyee');
select verifier('D', 'Kevin ne peut pas être re-sollicité',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) like '%personne_indisponible%');
select en_tant_que(:'E', format('select retirer_remplacant(%L)', :'k')) as r \gset
select verifier('D', 'Kevin (refusé) peut être retiré de la liste',
  :'r' = 'OK' and not exists (select 1 from remplacants where id = :'k'), :'r');

-- ===================================================================
-- E. Camille accepte puis se désiste
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'t')) as r \gset
select en_tant_que(:'T', format('select repondre_demande_remplacement(%L, false)', :'t')) as r \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'c')) as r \gset
select en_tant_que(:'C', format('select repondre_demande_remplacement(%L, true)', :'c')) as r \gset
select verifier('E', 'avant désistement : Camille sel, Kevin clôturé, Thomas refusé',
  statut_fiche(:'c') = 'acceptee+sel' and statut_fiche(:'k') = 'cloturee' and statut_fiche(:'t') = 'refusee');
select verifier('E', 'Kevin ne peut pas se désister à la place de Camille',
  en_tant_que(:'K', format('select se_desister_du_remplacement(%L)', :'c')) like '%Non autorisé%');
select count(*) as n0 from notifications_log \gset
select verifier('E', 'Camille se désiste',
  en_tant_que(:'C', format('select se_desister_du_remplacement(%L)', :'c')) = 'OK');
select verifier('E', 'Camille désistée, plus sélectionnée', statut_fiche(:'c') = 'desistee');
select verifier('E', 'Kevin redevient disponible', statut_fiche(:'k') = 'null');
select verifier('E', 'Thomas reste indisponible', statut_fiche(:'t') = 'refusee');
select verifier('E', 'pas d''annulation double absence', (select statut from pactes where id = :'p') = 'confirme');
select verifier('E', 'aucune notification automatique', (select count(*) from notifications_log where id > :n0) = 0);
select verifier('E', 'Camille ne peut pas ré-accepter',
  en_tant_que(:'C', format('select repondre_demande_remplacement(%L, true)', :'c')) like '%demande_non_active%');
select verifier('E', 'Camille ne peut pas être re-sollicitée',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'c')) like '%personne_indisponible%');
select verifier('E', 'Eliot peut re-solliciter Kevin',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) = 'OK');
select verifier('E', 'Kevin peut alors accepter',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) = 'OK' and statut_fiche(:'k') = 'acceptee+sel');

-- ===================================================================
-- F. Eliot ajoute une nouvelle personne pendant l'imprévu
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, false)', :'k')) as r \gset
select count(*) as n0 from notifications_log \gset
select verifier('F', 'ajout + demande en une action (Zoé, a un compte)',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'Zoé', 'Z', ' 0600000006 ')) = 'OK');
select id as z from remplacants where pacte_id = :'p' and prenom = 'Zoé' \gset
select verifier('F', 'Zoé en attente, compte lié côté serveur',
  statut_fiche(:'z') = 'envoyee' and (select profil_id from remplacants where id = :'z') = :'Z');
select verifier('F', 'Zoé notifiée', (select count(*) from notifications_log where id > :n0 and profile_id = :'Z') = 1);
select en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'Nina', 'N', '0700000000')) as r \gset
select verifier('F', 'ajout + demande (Nina, pas encore de compte)',
  :'r' = 'OK' and (select demande_statut from remplacants where pacte_id = :'p' and prenom = 'Nina') = 'envoyee'
  and (select profil_id from remplacants where pacte_id = :'p' and prenom = 'Nina') is null, :'r');
select verifier('F', 'David ne peut pas ajouter côté Eliot',
  en_tant_que(:'D', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'Intrus', 'I', '0700000001')) like '%Non autorisé%');
select bool_and(en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'P' || g, 'X', '070000001' || g)) = 'OK') as tous_ok
  from generate_series(1, 5) g \gset
select verifier('F', 'pas de plafond : 8 personnes du même côté',
  :'tous_ok' and (select count(*) from remplacants where pacte_id = :'p' and cote = 'initiateur') = 8);
select en_tant_que(:'Z', format('select repondre_demande_remplacement(%L, true)', :'z')) as r \gset
select count(*) as nrows from remplacants where pacte_id = :'p' \gset
select verifier('F', 'après acceptation, ajout impossible et rien n''est inséré',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'Tard', 'T', '0700000002')) like '%place_deja_prise%'
  and (select count(*) from remplacants where pacte_id = :'p') = :nrows);

-- ===================================================================
-- G. Kevin prévu des deux côtés → accepte Eliot → indisponible côté David
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Thomas', '0600000005') as td \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'ke')) as r \gset
select en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'kd')) as r \gset
select verifier('G', 'Kevin sollicité des deux côtés', statut_fiche(:'ke') = 'envoyee' and statut_fiche(:'kd') = 'envoyee');
select count(*) as n0 from notifications_log \gset
select verifier('G', 'Kevin accepte la place d''Eliot',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'ke')) = 'OK');
select verifier('G', 'demande de David clôturée automatiquement', statut_fiche(:'kd') = 'cloturee');
select verifier('G', 'aucune notification à David', (select count(*) from notifications_log where id > :n0 and profile_id = :'D') = 0);
select verifier('G', 'aucune notification à Kevin pour la clôture côté David',
  (select count(*) from notifications_log where id > :n0 and profile_id = :'K') = 0);
select verifier('G', 'David ne voit aucune fiche côté Eliot',
  compter_en_tant_que(:'D', format('select count(*) from remplacants where pacte_id = %L and cote = %L', :'p', 'initiateur')) = 0);
select verifier('G', 'David ne voit qu''un statut "cloturee" sur Kevin, rien d''autre',
  compter_en_tant_que(:'D', format(
    'select count(*) from remplacants where id = %L and demande_statut = %L and selectionne = false', :'kd', 'cloturee')) = 1);
select verifier('G', 'le Swend reste scellé pour David', (select statut from pactes where id = :'p') = 'confirme');
select verifier('G', 'David ne peut pas re-solliciter Kevin',
  en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'kd')) like '%personne_indisponible%');
select verifier('G', 'Kevin ne peut pas accepter côté David',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'kd')) like '%place_deja_prise%');
select verifier('G', 'David retire puis ré-ajoute Kevin : il renaît indisponible',
  en_tant_que(:'D', format('select retirer_remplacant(%L)', :'kd')) = 'OK'
  and statut_fiche(ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003')) = 'cloturee');
select id as kd from remplacants where pacte_id = :'p' and cote = 'destinataire' and prenom = 'Kevin' \gset
select count(*) as nrows from remplacants where pacte_id = :'p' \gset
select verifier('G', 'ajout+demande de Kevin par David refusé (déjà dans sa liste), rien inséré',
  en_tant_que(:'D', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'destinataire', 'Kevin', 'A', '0600000003')) like '%personne_deja_prevue%'
  and (select count(*) from remplacants where pacte_id = :'p') = :nrows);
select verifier('G', 'Thomas reste sollicitable par David',
  en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'td')) = 'OK');
select verifier('G', 'Kevin se désiste côté Eliot → redevient disponible côté David',
  en_tant_que(:'K', format('select se_desister_du_remplacement(%L)', :'ke')) = 'OK'
  and statut_fiche(:'ke') = 'desistee' and statut_fiche(:'kd') = 'null');

-- Variante : Kevin jamais sollicité par David
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'ke')) as r \gset
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'ke')) as r \gset
select verifier('G', 'fiche jamais sollicitée côté David → indisponible', statut_fiche(:'kd') = 'cloturee');

-- Variante : Kevin absent de la liste de David, qui l'ajoute pendant son imprévu
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'ke')) as r \gset
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'ke')) as r \gset
select count(*) as nrows from remplacants where pacte_id = :'p' \gset
select verifier('G', 'David ajoute Kevin (engagé côté Eliot) pendant l''imprévu : "indisponible", rien inséré',
  en_tant_que(:'D', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'destinataire', 'Kevin', 'A', '+33 6 00 00 00 03')) like '%personne_indisponible%'
  and (select count(*) from remplacants where pacte_id = :'p') = :nrows);

-- ===================================================================
-- H. Camille remplace Eliot + Thomas remplace David → annulation
-- ===================================================================
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Thomas', '0600000005') as t \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'c')) as r \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'t')) as r \gset
select en_tant_que(:'C', format('select repondre_demande_remplacement(%L, true)', :'c')) as r \gset
select verifier('H', 'un seul côté remplacé : Swend continue', (select statut from pactes where id = :'p') = 'confirme');
select verifier('H', 'Thomas accepte la place de David',
  en_tant_que(:'T', format('select repondre_demande_remplacement(%L, true)', :'t')) = 'OK');
select verifier('H', 'Swend annulé pour double remplacement', (select statut from pactes where id = :'p') = 'annuleDoubleAbsence');
select verifier('H', 'plus aucune action possible ensuite (désistement)',
  en_tant_que(:'T', format('select se_desister_du_remplacement(%L)', :'t')) like '%swend_inactif%');
select verifier('H', 'plus aucune demande possible ensuite',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) like '%swend_inactif%');
select verifier('H', 'plus aucune acceptation possible ensuite',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) like '%swend_inactif%');

-- ---------- bilan ----------
select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail
from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
