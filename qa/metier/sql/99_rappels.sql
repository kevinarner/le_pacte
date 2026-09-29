-- Rappels automatiques autour du Jour J et push de double remplacement
-- (D-021). Déterministe : le moteur est appelé avec un instant de référence
-- (envoyer_rappels_dus(p_maintenant)), jamais avec l'horloge réelle.
-- Utilise les outils de 10_imprevu.sql (verifier, en_tant_que, ajouter_fiche).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'

-- Swend scellé Eliot / David, le (lundi) 12 octobre 2037 à 20h00 (Paris) par défaut (calendrier identique à 2026, loin de l’horloge réelle : les gardes « après l’heure » de D-023a ne s’appliquent pas).
create or replace function swend_rappels(p_date timestamptz default '2037-10-12 18:00+00', p_type text default 'diner')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, type, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
                      destinataire_id, destinataire_nom, destinataire_telephone)
  values ('confirme', p_type, p_date, '00000000-0000-0000-0000-0000000000aa',
          '00000000-0000-0000-0000-00000000000e', 'Eliot E',
          '00000000-0000-0000-0000-00000000000d', 'David D', '06 00 00 00 02')
  returning id into v;
  return v;
end $$;
-- Rappels d'un Swend reçus par une personne : « type|titre|corps » dans l'ordre d'envoi.
create or replace function rappels_de(p uuid, p_profil uuid) returns text language sql as $$
  select coalesce(string_agg(data->>'rappel' || '|' || titre || '|' || corps, ' ## ' order by id), '')
  from notifications_log where data->>'type' = 'rappel' and data->>'pacte_id' = p::text and profile_id = p_profil
$$;
create or replace function nb_rappels(p uuid) returns int language sql as $$
  select count(*)::int from notifications_log where data->>'type' = 'rappel' and data->>'pacte_id' = p::text
$$;
-- Exécute le moteur à un instant donné et renvoie le nombre de push de ce Swend.
create or replace function rappels_a(p uuid, p_instant timestamptz) returns int language plpgsql as $$
declare avant int := nb_rappels(p);
begin
  perform envoyer_rappels_dus(p_instant);
  return nb_rappels(p) - avant;
end $$;
create or replace function demande_acceptee(p_titulaire uuid, p_personne uuid, p_fiche uuid) returns void language plpgsql as $$
begin
  if en_tant_que(p_titulaire, format('select envoyer_demande_remplacement(%L)', p_fiche)) <> 'OK'
     or en_tant_que(p_personne, format('select repondre_demande_remplacement(%L, true)', p_fiche)) <> 'OK' then
    raise exception 'acceptation impossible';
  end if;
end $$;

\set J7 '2037-10-05 16:00+00'
\set J3 '2037-10-09 16:00+00'
\set J1 '2037-10-11 16:00+00'
\set J0 '2037-10-12 15:00+00'
\set DATE '« lundi 12 octobre à 20h00 · Au Père Lapin »'

-- ===================================================================
-- T. Calendrier (Europe/Paris, changement d'heure)
-- ===================================================================
select verifier('T', 'J-7, J-3, J-1 à 18h Paris ; Jour J à H-3 (heure d''été)',
  echeance_rappel('2037-10-12 18:00+00', 'j7') = :'J7' and echeance_rappel('2037-10-12 18:00+00', 'j3') = :'J3'
  and echeance_rappel('2037-10-12 18:00+00', 'j1') = :'J1' and echeance_rappel('2037-10-12 18:00+00', 'j0') = :'J0');
select verifier('T', 'changement d''heure (25/10) : J-3 à 18h CEST = 16h UTC, J-1 à 18h CET = 17h UTC',
  echeance_rappel('2037-10-26 19:00+00', 'j3') = '2037-10-23 16:00+00'
  and echeance_rappel('2037-10-26 19:00+00', 'j1') = '2037-10-25 17:00+00'
  and echeance_rappel('2037-10-26 19:00+00', 'j0') = '2037-10-26 16:00+00');
select verifier('T', 'formats : « lundi 12 octobre », « 20h00 »',
  date_rappel_fr('2037-10-12 18:00+00') = 'lundi 12 octobre' and heure_rappel_fr('2037-10-12 18:00+00') = '20h00');

-- ===================================================================
-- N. Cadence et textes « repas » (Eliot ↔ David, sans remplacement)
-- ===================================================================
select swend_rappels() as p \gset
select verifier('N', 'aucun envoi avant l''heure (J-7 moins 1 minute)', rappels_a(:'p', '2037-10-05 15:59+00') = 0);
select verifier('N', 'J-7 à 18h00 Paris : Eliot et David', rappels_a(:'p', :'J7') = 2);
select verifier('N', 'J-7 Eliot : texte validé, prénom de David',
  rappels_de(:'p', :'E') = 'j7|Le compte à rebours est lancé|Votre Swend avec David approche : lundi 12 octobre à 20h00 · Au Père Lapin.',
  rappels_de(:'p', :'E'));
select verifier('N', 'J-7 David : texte validé, prénom d''Eliot',
  rappels_de(:'p', :'D') = 'j7|Le compte à rebours est lancé|Votre Swend avec Eliot approche : lundi 12 octobre à 20h00 · Au Père Lapin.',
  rappels_de(:'p', :'D'));
select verifier('N', 'moteur rejoué au même instant : aucune push en double', rappels_a(:'p', :'J7') = 0);
select verifier('N', 'moteur rejoué 10 minutes plus tard : aucune push en double', rappels_a(:'p', '2037-10-05 16:10+00') = 0);
select verifier('N', 'rien entre deux échéances', rappels_a(:'p', '2037-10-07 16:00+00') = 0);
select verifier('N', 'J-3 à 18h00 Paris', rappels_a(:'p', :'J3') = 2);
select verifier('N', 'J-1 à 18h00 Paris', rappels_a(:'p', :'J1') = 2);
select verifier('N', 'Jour J à H-3 (17h00 Paris)', rappels_a(:'p', :'J0') = 2);
select verifier('N', 'textes J-3, J-1, Jour J (Eliot)',
  rappels_de(:'p', :'E') = 'j7|Le compte à rebours est lancé|Votre Swend avec David approche : lundi 12 octobre à 20h00 · Au Père Lapin.'
    || ' ## j3|Ça se rapproche…|Plus que 3 jours avant votre Swend avec David : lundi 12 octobre à 20h00 · Au Père Lapin.'
    || ' ## j1|C’est demain !|Votre Swend avec David, c’est demain : lundi 12 octobre à 20h00 · Au Père Lapin.'
    || ' ## j0|C’est le jour du Swend !|Rendez-vous à 20h00 · Au Père Lapin. Est-ce que tu vas vraiment dîner avec David ?',
  rappels_de(:'p', :'E'));
select verifier('N', 'après le Jour J : plus rien', rappels_a(:'p', '2037-10-12 19:00+00') = 0);
select verifier('N', 'payload : type rappel + pacte_id + échéance, aucun rôle figé',
  (select bool_and((select array_agg(k order by k) from jsonb_object_keys(data) k) = array['pacte_id', 'rappel', 'type'])
   from notifications_log where data->>'type' = 'rappel' and data->>'pacte_id' = :'p'));
select swend_rappels(p_type := 'dejeuner') as pd \gset
select verifier('N', 'Jour J d''un déjeuner : « déjeuner avec »',
  rappels_a(:'pd', :'J0') = 2 and rappels_de(:'pd', :'D') like '%Est-ce que tu vas vraiment déjeuner avec Eliot ?');

-- ===================================================================
-- P. Pas de rattrapage, fenêtre d'envoi, changement d'heure
-- ===================================================================
select swend_rappels() as p \gset
select verifier('P', 'moteur découvert après J-7 et J-3 : seul J-1 part',
  rappels_a(:'p', '2037-10-11 16:05+00') = 2 and rappels_de(:'p', :'E') like 'j1|%' and rappels_de(:'p', :'E') not like '%j7|%');
select swend_rappels() as p \gset
select verifier('P', 'échéance manquée de plus de 30 minutes (panne) : ignorée', rappels_a(:'p', '2037-10-05 16:31+00') = 0);
select swend_rappels() as p \gset
select set_config('swend.rattrapage_scellement', 'on', false) as x \gset
update pactes set scelle_le = '2037-10-10 12:00+00' where id = :'p';
select set_config('swend.rattrapage_scellement', 'off', false) as x \gset
select verifier('P', 'Swend scellé à J-2 : jamais de J-7 ni de J-3', rappels_a(:'p', :'J7') = 0 and rappels_a(:'p', :'J3') = 0);
select verifier('P', 'Swend scellé à J-2 : J-1 puis Jour J normalement', rappels_a(:'p', :'J1') = 2 and rappels_a(:'p', :'J0') = 2);
select swend_rappels('2037-10-26 19:00+00') as p \gset
select verifier('P', 'heure d''hiver : rien à 17h00 Paris la veille', rappels_a(:'p', '2037-10-25 16:00+00') = 0);
select verifier('P', 'heure d''hiver : J-1 à 18h00 Paris (17h UTC), date du lundi 26 octobre',
  rappels_a(:'p', '2037-10-25 17:00+00') = 2 and rappels_de(:'p', :'E') like '%lundi 26 octobre à 20h00%');
insert into pactes (statut, type, date_retenue, dates_proposees, restaurant_id, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone)
values ('enAttenteReponse', 'diner', '2037-10-12 18:00+00', array['2037-10-12 18:00+00'::timestamptz], '00000000-0000-0000-0000-0000000000aa',
        :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02') returning id as pn \gset
select verifier('P', 'Swend non scellé : aucun rappel', rappels_a(:'pn', :'J1') = 0);

-- ===================================================================
-- R. Remplacement accepté : Kevin remplace Eliot
-- ===================================================================
select swend_rappels() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select demande_acceptee(:'E', :'K', :'k');
select verifier('R', 'J-7 : trois push (Eliot, Kevin, David)', rappels_a(:'p', :'J7') = 3);
select verifier('R', 'Eliot : « Kevin prend ta place »',
  rappels_de(:'p', :'E') = 'j7|Ton Swend approche|Lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n' || 'Kevin prend ta place.',
  rappels_de(:'p', :'E'));
select verifier('R', 'Kevin : rappel « repas » avec David',
  rappels_de(:'p', :'K') = 'j7|Le compte à rebours est lancé|Votre Swend avec David approche : lundi 12 octobre à 20h00 · Au Père Lapin.',
  rappels_de(:'p', :'K'));
select verifier('R', 'David : toujours avec Eliot, jamais Kevin',
  rappels_de(:'p', :'D') = 'j7|Le compte à rebours est lancé|Votre Swend avec Eliot approche : lundi 12 octobre à 20h00 · Au Père Lapin.',
  rappels_de(:'p', :'D'));
select verifier('R', 'textes « remplacé » J-3, J-1, Jour J',
  rappels_a(:'p', :'J3') = 3 and rappels_a(:'p', :'J1') = 3 and rappels_a(:'p', :'J0') = 3
  and rappels_de(:'p', :'E') like '%j3|Plus que 3 jours|Ton Swend est prévu lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n' || 'Kevin prend ta place.%'
  and rappels_de(:'p', :'E') like '%j1|C’est demain !|Ton Swend aura lieu lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n' || 'Kevin prend ta place.%'
  and rappels_de(:'p', :'E') like '%j0|C’est le jour du Swend !|Aujourd’hui, lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n' || 'Kevin prend ta place.',
  rappels_de(:'p', :'E'));
select verifier('R', 'Kevin, Jour J : « dîner avec David »', rappels_de(:'p', :'K') like '%Est-ce que tu vas vraiment dîner avec David ?');
select verifier('R', 'confidentialité : aucun rappel de David ne mentionne Kevin', rappels_de(:'p', :'D') not like '%Kevin%');
select verifier('R', 'destination au clic : Eliot remplacé → fiche, Kevin → fiche, David → fiche',
  (select en_tant_que(:'E', format('select destination_rappel(%L)', :'p'))) = 'OK'
  and compter_en_tant_que(:'E', format('select (destination_rappel(%L) = %L)::int', :'p', 'fiche')) = 1
  and compter_en_tant_que(:'K', format('select (destination_rappel(%L) = %L)::int', :'p', 'fiche')) = 1
  and compter_en_tant_que(:'D', format('select (destination_rappel(%L) = %L)::int', :'p', 'fiche')) = 1);

-- ===================================================================
-- B. Recherche en cours (pas de remplaçant accepté)
-- ===================================================================
select swend_rappels() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select verifier('B', 'demande en attente : Eliot en « cherche », David normal', rappels_a(:'p', :'J7') = 2
  and rappels_de(:'p', :'E') = 'j7|Ton Swend avec David approche|Lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n'
      || 'Tente de trouver quelqu’un pour te remplacer tant qu’il en est encore temps.'
  and rappels_de(:'p', :'D') like 'j7|Le compte à rebours est lancé|Votre Swend avec Eliot approche%'
  and rappels_de(:'p', :'K') = '', rappels_de(:'p', :'E'));
select verifier('B', 'destination au clic : Eliot → Un imprévu ? ; David → fiche',
  compter_en_tant_que(:'E', format('select (destination_rappel(%L) = %L)::int', :'p', 'imprevu')) = 1
  and compter_en_tant_que(:'D', format('select (destination_rappel(%L) = %L)::int', :'p', 'fiche')) = 1);
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, false)', :'k')) as r \gset
select verifier('B', 'refus sans nouvelle demande : Eliot reste en « cherche » (J-3, J-1, Jour J)',
  rappels_a(:'p', :'J3') = 2 and rappels_a(:'p', :'J1') = 2 and rappels_a(:'p', :'J0') = 2
  and rappels_de(:'p', :'E') like '%j3|Plus que 3 jours pour ton Swend avec David|Lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n' || 'Tente de trouver%'
  and rappels_de(:'p', :'E') like '%j1|C’est demain !|Ton Swend avec David : lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n'
      || 'Le temps presse, essaie de trouver quelqu’un pour te remplacer au plus vite.%'
  and rappels_de(:'p', :'E') like '%j0|Ton Swend avec David est dans 3h !|Aujourd’hui à 20h00 · Au Père Lapin.' || E'\n'
      || 'Ton Swend est en péril ! Trouve quelqu’un pour te remplacer dès que possible. Et si vraiment personne n’est disponible, annule le Swend pour que le restaurant soit prévenu.',
  rappels_de(:'p', :'E'));
select verifier('B', 'David : rappels normaux avec Eliot, sans indice', rappels_de(:'p', :'D') not like '%remplacer%' and rappels_de(:'p', :'D') not like '%Kevin%');
select swend_rappels() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select en_tant_que(:'E', format('select annuler_demande_remplacement(%L)', :'k')) as r \gset
select verifier('B', 'toutes les demandes annulées (sans refus) : Eliot redevient normal',
  rappels_a(:'p', :'J7') = 2 and rappels_de(:'p', :'E') like 'j7|Le compte à rebours est lancé|%'
  and compter_en_tant_que(:'E', format('select (destination_rappel(%L) = %L)::int', :'p', 'fiche')) = 1);

-- ===================================================================
-- D. Désistement puis nouvelle acceptation (état recalculé à chaque envoi)
-- ===================================================================
select swend_rappels() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select demande_acceptee(:'E', :'K', :'k');
select verifier('D', 'J-7 : Kevin remplace Eliot', rappels_a(:'p', :'J7') = 3 and rappels_de(:'p', :'K') like 'j7|%');
select en_tant_que(:'K', format('select se_desister_du_remplacement(%L)', :'k')) as r \gset
select verifier('D', 'Kevin désisté : J-3 → Eliot « cherche », David normal, plus rien pour Kevin',
  rappels_a(:'p', :'J3') = 2
  and rappels_de(:'p', :'E') like '%j3|Plus que 3 jours pour ton Swend avec David|%'
  and rappels_de(:'p', :'D') like '%j3|Ça se rapproche…|Plus que 3 jours avant votre Swend avec Eliot%'
  and rappels_de(:'p', :'K') not like '%j3|%', rappels_de(:'p', :'E'));
select verifier('D', 'Kevin désisté : plus de destination au clic',
  compter_en_tant_que(:'K', format('select (destination_rappel(%L) is null)::int', :'p')) = 1);
select demande_acceptee(:'E', :'C', :'c');
select verifier('D', 'Camille accepte : J-1 → Camille « repas » avec David, Eliot « Camille prend ta place », David avec Eliot',
  rappels_a(:'p', :'J1') = 3
  and rappels_de(:'p', :'C') = 'j1|C’est demain !|Votre Swend avec David, c’est demain : lundi 12 octobre à 20h00 · Au Père Lapin.'
  and rappels_de(:'p', :'E') like '%j1|C’est demain !|Ton Swend aura lieu lundi 12 octobre à 20h00 · Au Père Lapin.' || E'\n' || 'Camille prend ta place.'
  and rappels_de(:'p', :'D') like '%j1|C’est demain !|Votre Swend avec Eliot, c’est demain%'
  and rappels_de(:'p', :'K') not like '%j1|%', rappels_de(:'p', :'C'));
select verifier('D', 'confidentialité : David n''a jamais vu Kevin ni Camille',
  rappels_de(:'p', :'D') not like '%Kevin%' and rappels_de(:'p', :'D') not like '%Camille%');

-- Acceptation après une échéance : pas de rappel rétroactif.
select swend_rappels() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) as r \gset
select verifier('D', 'J-3 traité (Eliot en recherche)', rappels_a(:'p', :'J3') = 2);
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) as r \gset
select verifier('D', 'Kevin accepte après J-3 : aucun J-3 rétroactif, même dans la fenêtre', rappels_a(:'p', '2037-10-09 16:10+00') = 0
  and rappels_de(:'p', :'K') = '');
select verifier('D', 'Kevin reçoit le J-1 suivant', rappels_a(:'p', :'J1') = 3 and rappels_de(:'p', :'K') like 'j1|%');
select verifier('D', 'clic sur l''ancienne push « cherche » d''Eliot : destination recalculée (fiche, plus Un imprévu ?)',
  compter_en_tant_que(:'E', format('select (destination_rappel(%L) = %L)::int', :'p', 'fiche')) = 1);

-- ===================================================================
-- A. Swend annulé : aucun rappel futur
-- ===================================================================
select swend_rappels() as p \gset
select verifier('A', 'J-7 envoyé', rappels_a(:'p', :'J7') = 2);
-- (écriture serveur : l'annulation elle-même est testée dans 97_annulation_manuelle.sql)
update pactes set statut = 'annule' where id = :'p';
select verifier('A', 'Swend annulé : plus aucun rappel', rappels_a(:'p', :'J3') = 0 and rappels_a(:'p', :'J1') = 0 and rappels_a(:'p', :'J0') = 0);

-- ===================================================================
-- X. Double remplacement : push immédiate
-- ===================================================================
select swend_rappels() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Camille', '0600000004') as c \gset
select demande_acceptee(:'E', :'K', :'k');
select verifier('X', 'J-7 envoyé tant que le Swend tient', rappels_a(:'p', :'J7') = 3);
select en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'c')) as r \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select en_tant_que(:'C', format('select repondre_demande_remplacement(%L, true)', :'c')) as r \gset
create or replace function push_depuis(p_n0 bigint, p_profil uuid) returns text language sql as $$
  select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where id > p_n0 and profile_id = p_profil
$$;
select verifier('X', 'Swend annulé pour double remplacement', (select statut from pactes where id = :'p') = 'annuleDoubleAbsence');
select verifier('X', 'Eliot : « Ton Swend est annulé », avec David',
  push_depuis(:n0, :'E') = 'Ton Swend est annulé|Toi et David avez chacun fait appel à quelqu’un pour prendre votre place. Le Swend du lundi 12 octobre à 20h00 · Au Père Lapin est annulé.',
  push_depuis(:n0, :'E'));
select verifier('X', 'David : « Ton Swend est annulé », avec Eliot — et pas de push « Camille a accepté »',
  push_depuis(:n0, :'D') = 'Ton Swend est annulé|Toi et Eliot avez chacun fait appel à quelqu’un pour prendre votre place. Le Swend du lundi 12 octobre à 20h00 · Au Père Lapin est annulé.',
  push_depuis(:n0, :'D'));
select verifier('X', 'Kevin (remplaçant d''Eliot) : « Le Swend est annulé », sans le nom de Camille',
  push_depuis(:n0, :'K') = 'Le Swend est annulé|Tu n’as finalement plus besoin de prendre la place d’Eliot lundi 12 octobre à 20h00 · Au Père Lapin : David a lui aussi fait appel à quelqu’un pour le remplacer.',
  push_depuis(:n0, :'K'));
select verifier('X', 'Camille (remplaçante de David) : « Le Swend est annulé », sans le nom de Kevin',
  push_depuis(:n0, :'C') = 'Le Swend est annulé|Tu n’as finalement plus besoin de prendre la place de David lundi 12 octobre à 20h00 · Au Père Lapin : Eliot a lui aussi fait appel à quelqu’un pour le remplacer.',
  push_depuis(:n0, :'C'));
select verifier('X', 'exactement 4 push, vers la fiche du Swend',
  (select count(*) from notifications_log where id > :n0) = 4
  and (select bool_and(data->>'type' = 'pacte' and data->>'pacte_id' = :'p') from notifications_log where id > :n0));
select verifier('X', 'plus aucun rappel ensuite', rappels_a(:'p', :'J3') = 0 and rappels_a(:'p', :'J1') = 0 and rappels_a(:'p', :'J0') = 0);
select verifier('X', 'une acceptation simple (sans double remplacement) reste notifiée au titulaire (D-015)',
  (select count(*) from notifications_log where profile_id = :'E' and corps = 'Kevin a accepté de prendre votre place.'
     and data->>'remplacant_id' = :'k') = 1);

-- ===================================================================
-- L. Élision du prénom (« d’Eliot », « de David »), même règle que l'app
-- ===================================================================
select verifier('L', 'voyelle, voyelle accentuée, h, y : élision',
  de_prenom('Eliot') = 'd’Eliot' and de_prenom('Émile') = 'd’Émile' and de_prenom('hugo') = 'd’hugo'
  and de_prenom('Hélène') = 'd’Hélène' and de_prenom('Yves') = 'd’Yves' and de_prenom('Anna') = 'd’Anna');
select verifier('L', 'consonne : « de »', de_prenom('David') = 'de David' and de_prenom('Kevin') = 'de Kevin'
  and de_prenom('Camille') = 'de Camille');
select verifier('L', 'espaces ignorés, prénom vide sans erreur', de_prenom('  Eliot ') = 'd’Eliot' and de_prenom('') = 'de ' and de_prenom(null) = 'de ');

-- ===================================================================
-- S. Sécurité
-- ===================================================================
select verifier('S', 'l''app ne lit pas le journal des rappels',
  en_tant_que(:'E', 'select count(*) from rappels_envoyes') like '%permission denied%'
  and en_tant_que(:'E', 'select count(*) from rappels_echeances') like '%permission denied%');
select verifier('S', 'l''app ne peut pas déclencher le moteur',
  en_tant_que(:'E', 'select envoyer_rappels_dus()') like '%permission denied%');
select verifier('S', 'un inconnu n''obtient aucune destination',
  compter_en_tant_que('00000000-0000-0000-0000-00000000000f', format('select (destination_rappel(%L) is null)::int', :'p')) = 1);

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
