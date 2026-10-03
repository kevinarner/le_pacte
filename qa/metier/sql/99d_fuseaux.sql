-- Convention temporelle (R2) et date retenue parmi les dates proposées
-- (D-025b). Utilise les outils de 10_imprevu.sql (verifier, en_tant_que) et
-- de 99c_delai_minimum.sql (dm_lire). La base de test est en UTC, comme la
-- production : une chaîne sans fuseau y serait lue en UTC (19:00 → 20:00 à
-- Paris en hiver), d'où son refus.
--
-- Cas : hiver, été, lendemain du passage à l'heure d'hiver (dernier dimanche
-- d'octobre) et à l'heure d'été (dernier dimanche de mars). Swends enregistrés
-- en 2031 (jamais périmés) ; calculs purs aussi sur les cas 2026-2027 du
-- diagnostic.
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
-- Cette suite crée plusieurs Swends Eliot ↔ David au nom des utilisateurs :
-- la règle « un Swend en cours par paire » (D-023c, testée par
-- 99e_nouveau_swend.sql) est suspendue le temps de la suite, puis rétablie.
alter table pactes disable trigger trg_verrou_un_swend_par_paire;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'

-- ---------- outils ----------
-- Instant d'une heure murale de Paris.
create or replace function fz_paris(p text) returns timestamptz language sql stable as $$
  select p::timestamp at time zone 'Europe/Paris'
$$;
create or replace function fz_utc(p timestamptz) returns text language sql stable as $$
  select to_char(p at time zone 'UTC', 'YYYY-MM-DD HH24:MI"Z"')
$$;
-- Création « comme l'app » (Eliot, utilisateur standard) avec les dates JSON
-- exactement telles qu'envoyées : l'id, ou l'erreur.
create or replace function fz_creer(p_dates text) returns text language sql as $$
  select dm_lire('00000000-0000-0000-0000-00000000000e', format(
    $q$insert into pactes (type, statut, dates_proposees, restaurant_id, initiateur_id, initiateur_nom,
       destinataire_id, destinataire_nom, destinataire_telephone)
       values ('diner', 'enAttenteChoixDateDestinataire', %L::jsonb, '00000000-0000-0000-0000-0000000000aa',
       '00000000-0000-0000-0000-00000000000e', 'Eliot E', '00000000-0000-0000-0000-00000000000d', 'David D',
       '0600000002') returning id::text$q$, p_dates))
$$;
-- Choix d'une date « comme l'app » (David), valeur JSON telle qu'envoyée
-- (PostgREST la convertit en timestamptz dans le fuseau de session, UTC).
create or replace function fz_choisir(p uuid, p_valeur text) returns text language sql as $$
  select dm_lire('00000000-0000-0000-0000-00000000000d', format(
    $q$update pactes set date_retenue = %L, statut = 'enAttenteReponse' where id = %L returning 'OK'$q$, p_valeur, p))
$$;
create or replace function fz_contre(p uuid, p_dates text) returns text language sql as $$
  select dm_lire('00000000-0000-0000-0000-00000000000d', format(
    $q$update pactes set dates_proposees = %L::jsonb, nombre_echanges_date = nombre_echanges_date + 1,
       statut = 'enAttenteChoixDateInitiateur' where id = %L returning 'OK'$q$, p_dates, p))
$$;
create or replace function fz_dates(p uuid) returns text language sql as $$
  select dates_proposees::text from pactes where id = p
$$;

-- ===================================================================
-- F. Format des dates proposées : instant explicite, forme canonique
-- ===================================================================
select fz_creer('["2031-11-18T18:00:00.000Z"]') as f1 \gset
select verifier('F', 'nouvelle app : 19:00 à Paris envoyé en UTC (Z) → accepté, enregistré tel quel',
  :'f1' ~ '^[0-9a-f-]{36}$' and fz_dates(:'f1') = '["2031-11-18T18:00:00.000Z"]', :'f1');
select fz_creer('["2031-11-18T19:00:00+01:00", "2031-07-08T19:00:00+02:00"]') as f2 \gset
select verifier('F', 'offset explicite (+01:00 / +02:00) → accepté, forme canonique UTC',
  fz_dates(:'f2') = '["2031-11-18T18:00:00.000Z", "2031-07-08T17:00:00.000Z"]', fz_dates(:'f2'));
select verifier('F', 'ancienne app : chaîne sans fuseau refusée (date_sans_fuseau), rien n''est créé',
  fz_creer('["2031-11-18T19:00:00.000"]') like '%date_sans_fuseau%');
select verifier('F', 'une seule chaîne sans fuseau parmi plusieurs : refus',
  fz_creer('["2031-11-18T18:00:00.000Z", "2031-11-19T19:00:00"]') like '%date_sans_fuseau%');
select verifier('F', 'valeur non textuelle ou dates non en tableau : refus',
  fz_creer('[1795000000]') like '%date_sans_fuseau%' and fz_creer('"2031-11-18T18:00:00Z"') like '%date_sans_fuseau%');
select verifier('F', 'contre-proposition sans fuseau refusée, dates inchangées',
  fz_contre(:'f1', '["2031-11-25T19:00:00.000"]') like '%date_sans_fuseau%'
  and fz_dates(:'f1') = '["2031-11-18T18:00:00.000Z"]');
select verifier('F', 'contre-proposition avec fuseau acceptée, forme canonique',
  fz_contre(:'f1', '["2031-11-25T19:00:00+01:00"]') = 'OK' and fz_dates(:'f1') = '["2031-11-25T18:00:00.000Z"]',
  fz_dates(:'f1'));
do $$
declare v text;
begin
  begin
    insert into pactes (type, statut, dates_proposees, restaurant_id, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone)
    values ('diner', 'enAttenteChoixDateDestinataire', '["2031-11-18T19:00:00"]', '00000000-0000-0000-0000-0000000000aa',
            '00000000-0000-0000-0000-00000000000e', 'Eliot E', 'David D', '0600000002');
    v := 'accepté';
  exception when others then v := sqlerrm;
  end;
  perform verifier('F', 'SQL Editor / fonctions serveur aussi : jamais de chaîne sans fuseau', v = 'date_sans_fuseau', v);
end $$;

-- ===================================================================
-- B. D-025b : la date retenue est l'une des dates proposées
-- ===================================================================
select fz_creer('["2031-11-18T18:00:00.000Z", "2031-11-19T18:00:00.000Z"]') as b \gset
select fz_choisir(:'b', '2031-11-18T19:00:00.000') as r \gset
select verifier('B', 'ancienne app : 19:00 sans fuseau (lu 20:00 à Paris) → refusé, rien ne change',
  :'r' like '%date_non_proposee%'
  and (select date_retenue is null and statut = 'enAttenteChoixDateDestinataire' from pactes where id = :'b'), :'r');
select verifier('B', 'date absente des propositions → refusée',
  fz_choisir(:'b', '2031-11-20T18:00:00.000Z') like '%date_non_proposee%');
select fz_choisir(:'b', '2031-11-18T19:00:00+01:00') as r \gset
select verifier('B', 'même instant écrit autrement (+01:00) → accepté',
  :'r' = 'OK' and (select date_retenue from pactes where id = :'b') = fz_paris('2031-11-18 19:00'), :'r');
select verifier('B', 'nouvelle app : instant UTC (Z) d''une date proposée → accepté',
  fz_choisir(fz_creer('["2031-07-08T17:00:00.000Z"]')::uuid, '2031-07-08T17:00:00.000Z') = 'OK');
select verifier('B', 'création avec une date retenue non proposée → refusée',
  dm_lire(:'E', $q$insert into pactes (type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id,
     initiateur_nom, destinataire_nom, destinataire_telephone) values ('diner', 'enAttenteReponse',
     '["2031-11-18T18:00:00.000Z"]', '2031-11-18T19:00:00', '00000000-0000-0000-0000-0000000000aa',
     '00000000-0000-0000-0000-00000000000e', 'X', 'Y', '0600000002') returning 'OK'$q$) like '%date_non_proposee%');
-- D-025b est un invariant : aussi pour le SQL Editor et les fonctions serveur.
do $$
declare v text; w text; x text;
begin
  begin
    update pactes set date_retenue = fz_paris('2031-11-21 19:00') where dates_proposees = '["2031-11-18T18:00:00.000Z", "2031-11-19T18:00:00.000Z"]';
    v := 'accepté';
  exception when others then v := sqlerrm;
  end;
  perform verifier('B', 'SQL Editor / fonction serveur : date retenue hors des dates proposées refusée', v = 'date_non_proposee', v);
  begin
    insert into pactes (type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone)
    values ('diner', 'confirme', '[]', fz_paris('2031-11-18 19:00'), '00000000-0000-0000-0000-0000000000aa',
            '00000000-0000-0000-0000-00000000000e', 'Eliot E', 'David D', '0600000002');
    w := 'accepté';
  exception when others then w := sqlerrm;
  end;
  perform verifier('B', 'SQL Editor : Swend scellé sans date proposée refusé', w = 'date_non_proposee', w);
  -- Swend en négociation portant déjà une date retenue (état cohérent) : une
  -- contre-proposition qui ne la contient plus est refusée.
  insert into pactes (id, type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone)
  values ('00000000-0000-4000-9d00-000000000003', 'diner', 'enAttenteChoixDateDestinataire', '["2031-11-18T18:00:00.000Z"]',
          fz_paris('2031-11-18 19:00'), '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-00000000000e', 'Eliot E', 'David D', '0600000002');
  begin
    update pactes set dates_proposees = '["2031-11-19T18:00:00.000Z"]', nombre_echanges_date = 1
    where id = '00000000-0000-4000-9d00-000000000003';
    x := 'accepté';
  exception when others then x := sqlerrm;
  end;
  perform verifier('B', 'retirer la date retenue des dates proposées : refusé (D-025b vérifié aussi sur ce changement)', x = 'date_non_proposee', x);
end $$;
select qa.deplacer_swend(:'b', fz_paris('2031-11-21 19:00'));
select verifier('B', 'outil de test qa.deplacer_swend : date retenue et dates proposées déplacées ensemble',
  (select date_retenue = fz_paris('2031-11-21 19:00') and dates_proposees = '["2031-11-21T18:00:00.000Z"]' from pactes where id = :'b'));
-- ===================================================================
-- M. D-025 : Swend d'un utilisateur standard créé pendant que le déclencheur
--    était désactivé (cas de production 6cb94c32, date_minimale NULL)
-- ===================================================================
insert into pactes (id, type, statut, dates_proposees, restaurant_id, initiateur_id, initiateur_nom,
                    destinataire_id, destinataire_nom, destinataire_telephone)
values ('00000000-0000-4000-9d00-000000000010', 'diner', 'enAttenteChoixDateDestinataire',
        to_jsonb(array[dm_jour(60)]), '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '0600000002');
select verifier('M', 'date_minimale NULL (créé hors app / déclencheur désactivé) : contre-proposition à J+3 acceptée (contournement)',
  fz_contre('00000000-0000-4000-9d00-000000000010', format('[%s]', to_json(dm_jour(3)))) = 'OK');
-- Correction R2-01 : seule date_minimale est posée (jour de création à Paris
-- + 15), hors app ; la négociation continue là où elle en est.
update pactes set date_minimale = date_minimale_swend(created_at)
where id = '00000000-0000-4000-9d00-000000000010';
select verifier('M', 'après correction : contre-proposition à J+3 refusée (date_trop_proche)',
  fz_contre('00000000-0000-4000-9d00-000000000010', format('[%s]', to_json(dm_jour(3)))) like '%date_trop_proche%');
select verifier('M', 'après correction : contre-proposition à J+20 acceptée',
  fz_contre('00000000-0000-4000-9d00-000000000010', format('[%s]', to_json(dm_jour(20)))) = 'OK');
select verifier('M', 'après correction : choix d''une date proposée à J+20 accepté (D-025 et D-025b)',
  fz_choisir('00000000-0000-4000-9d00-000000000010', to_json(dm_jour(20)) #>> '{}') = 'OK');
select verifier('M', 'l''app ne peut pas effacer ni modifier date_minimale',
  dm_lire(:'D', $q$update pactes set date_minimale = null where id = '00000000-0000-4000-9d00-000000000010' returning 'OK'$q$)
    like '%modification_interdite%');

-- ===================================================================
-- H. Un Swend choisi à 19:00 à Paris reste à 19:00 partout
-- ===================================================================
create temp table fz_cas (nom text, murale text, attendu_utc text, j0 text, j1 text, j3 text, j7 text, chat text, push text);
insert into fz_cas values
 ('hiver',                   '2031-11-18 19:00', '2031-11-18 18:00Z', '2031-11-18 15:00Z', '2031-11-17 17:00Z', '2031-11-15 17:00Z', '2031-11-11 17:00Z', '2031-11-18 21:00Z', 'mardi 18 novembre à 19h00'),
 ('été',                     '2031-07-08 19:00', '2031-07-08 17:00Z', '2031-07-08 14:00Z', '2031-07-07 16:00Z', '2031-07-05 16:00Z', '2031-07-01 16:00Z', '2031-07-08 20:00Z', 'mardi 8 juillet à 19h00'),
 ('lendemain passage hiver', '2031-10-27 19:00', '2031-10-27 18:00Z', '2031-10-27 15:00Z', '2031-10-26 17:00Z', '2031-10-24 16:00Z', '2031-10-20 16:00Z', '2031-10-27 21:00Z', 'lundi 27 octobre à 19h00'),
 ('lendemain passage été',   '2031-03-31 19:00', '2031-03-31 17:00Z', '2031-03-31 14:00Z', '2031-03-30 16:00Z', '2031-03-28 17:00Z', '2031-03-24 17:00Z', '2031-03-31 20:00Z', 'lundi 31 mars à 19h00'),
 ('diagnostic 17/11/2026',   '2026-11-17 19:00', '2026-11-17 18:00Z', '2026-11-17 15:00Z', '2026-11-16 17:00Z', '2026-11-14 17:00Z', '2026-11-10 17:00Z', '2026-11-17 21:00Z', 'mardi 17 novembre à 19h00'),
 ('diagnostic été 2027',     '2027-07-06 19:00', '2027-07-06 17:00Z', '2027-07-06 14:00Z', '2027-07-05 16:00Z', '2027-07-03 16:00Z', '2027-06-29 16:00Z', '2027-07-06 20:00Z', 'mardi 6 juillet à 19h00');
select verifier('H', nom || ' : instant stocké ' || attendu_utc, fz_utc(fz_paris(murale)) = attendu_utc, fz_utc(fz_paris(murale)))
from fz_cas;
select verifier('H', nom || ' : push de négociation « ' || push || ' »',
  formater_date_heure_fr(fz_paris(murale)) = push, formater_date_heure_fr(fz_paris(murale))) from fz_cas;
select verifier('H', nom || ' : texte des rappels à 19h00', heure_rappel_fr(fz_paris(murale)) = '19h00'
  and (select t.corps from texte_rappel('repas', 'j1', fz_paris(murale), 'Au père Lapin', 'diner', 'David') t) like '%19h00%',
  heure_rappel_fr(fz_paris(murale))) from fz_cas;
select verifier('H', nom || ' : Jour J (H-3) = 16:00 à Paris, ' || j0, fz_utc(echeance_rappel(fz_paris(murale), 'j0')) = j0,
  fz_utc(echeance_rappel(fz_paris(murale), 'j0'))) from fz_cas;
select verifier('H', nom || ' : J-1 / J-3 / J-7 à 18:00 à Paris (offset du jour du rappel)',
  fz_utc(echeance_rappel(fz_paris(murale), 'j1')) = j1 and fz_utc(echeance_rappel(fz_paris(murale), 'j3')) = j3
  and fz_utc(echeance_rappel(fz_paris(murale), 'j7')) = j7,
  fz_utc(echeance_rappel(fz_paris(murale), 'j1')) || ' / ' || fz_utc(echeance_rappel(fz_paris(murale), 'j3')) || ' / '
  || fz_utc(echeance_rappel(fz_paris(murale), 'j7'))) from fz_cas;
select verifier('H', nom || ' : chat après le Swend à 22:00 à Paris (H+3)', fz_utc(ouverture_chat_apres_swend(fz_paris(murale))) = chat,
  fz_utc(ouverture_chat_apres_swend(fz_paris(murale)))) from fz_cas;
select verifier('H', 'chat : 20:00 en hiver → 23:00 (borne incluse), règle D-023b inchangée',
  fz_utc(ouverture_chat_apres_swend(fz_paris('2031-11-18 20:00'))) = '2031-11-18 22:00Z');
select verifier('H', 'chat : 21:45 en été → lendemain 10:00 à Paris, règle D-023b inchangée (D-026 non appliquée)',
  fz_utc(ouverture_chat_apres_swend(fz_paris('2031-07-08 21:45'))) = '2031-07-09 08:00Z');
select verifier('H', 'D-025 : J+15 sur le jour de Paris (création à 00:30 à Paris = 23:30 UTC la veille)',
  date_minimale_swend('2026-10-31 23:30+00') = '2026-11-16' and date_minimale_swend('2026-10-31 22:30+00') = '2026-11-15'
  and date_minimale_swend('2027-07-14 22:30+00') = '2027-07-30');

-- Un Swend scellé à 19:00 en hiver : vue des réservations, gel à H, rappel J-1.
insert into pactes (id, type, statut, dates_proposees, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
                    destinataire_id, destinataire_nom, destinataire_telephone)
values ('00000000-0000-4000-9d00-000000000001', 'diner', 'confirme', '["2031-11-18T18:00:00.000Z"]', fz_paris('2031-11-18 19:00'),
        '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '0600000002'),
       ('00000000-0000-4000-9d00-000000000002', 'diner', 'confirme', '["2031-03-31T17:00:00.000Z"]', fz_paris('2031-03-31 19:00'),
        '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '0600000002');
select verifier('H', 'vue des réservations : 18/11/2031 à 19:00 (pas 20:00)',
  (select date_rdv = '2031-11-18' and heure_rdv = '19:00' from reservations_a_suivre where swend_id = '00000000-0000-4000-9d00-000000000001'),
  (select date_rdv || ' ' || heure_rdv from reservations_a_suivre where swend_id = '00000000-0000-4000-9d00-000000000001'));
select figer_swends_passes(fz_paris('2031-11-18 18:59')) as n \gset
select verifier('H', 'gel à H : rien à 18:59 à Paris',
  not exists (select 1 from swends_figes where pacte_id = '00000000-0000-4000-9d00-000000000001'));
select figer_swends_passes(fz_paris('2031-11-18 19:00')) as n \gset
select verifier('H', 'gel à H : figé à 19:00 à Paris exactement (pas à 20:00)',
  exists (select 1 from swends_figes where pacte_id = '00000000-0000-4000-9d00-000000000001'));
select coalesce(max(id), 0) as avant from notifications_log \gset
select envoyer_rappels_dus(fz_paris('2031-03-30 18:00')) as n \gset
select verifier('H', 'rappel J-1 le jour du passage à l''heure d''été : envoyé à 18:00 à Paris, « à 19h00 »',
  exists (select 1 from rappels_envoyes where pacte_id = '00000000-0000-4000-9d00-000000000002' and type_rappel = 'j1')
  and exists (select 1 from notifications_log where id > :avant and corps like '%19h00%'),
  (select string_agg(corps, ' | ') from notifications_log where id > :avant));

alter table pactes enable trigger trg_verrou_un_swend_par_paire;
select case when ok then 'PASS' else 'FAIL' end as r, scenario, verif, detail from test_resultats order by id;
