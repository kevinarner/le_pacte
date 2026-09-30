-- D-019 (personnes de confiance actives seulement après scellage) et D-011
-- (au plus 2 contre-propositions de date au total). Utilise les outils de
-- 10_imprevu.sql (verifier, en_tant_que, compter_en_tant_que, ajouter_fiche).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'

-- Swend en négociation : Eliot propose la date A à David.
create or replace function swend_en_negociation() returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, dates_proposees, nombre_echanges_date, restaurant_id,
                      initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone)
  values ('enAttenteChoixDateDestinataire', array['2031-11-10 19:30+00'::timestamptz], 0,
          '00000000-0000-0000-0000-0000000000aa',
          '00000000-0000-0000-0000-00000000000e', 'Eliot E',
          '00000000-0000-0000-0000-00000000000d', 'David D', '06 00 00 00 02')
  returning id into v;
  return v;
end $$;
-- Ce que Kevin (personne de confiance) peut atteindre de ce Swend.
create or replace function vu_par_kevin(p uuid) returns text language plpgsql as $$
begin
  return compter_en_tant_que('00000000-0000-0000-0000-00000000000a', format('select count(*) from pactes where id = %L', p)) || '/'
      || compter_en_tant_que('00000000-0000-0000-0000-00000000000a', format('select count(*) from remplacants where pacte_id = %L', p)) || '/'
      || compter_en_tant_que('00000000-0000-0000-0000-00000000000a', format('select count(*) from messages m join remplacants r on r.id = m.remplacant_id where r.pacte_id = %L', p));
end $$;
-- Contre-proposition "comme l'app" : nouvelles dates, compteur +1, tour de l'autre.
create or replace function contre_proposer(p_qui uuid, p uuid, p_date text, p_compteur int, p_statut text) returns text
language sql as $$
  select en_tant_que(p_qui, format(
    'update pactes set dates_proposees = array[%L::timestamptz], nombre_echanges_date = %s, statut = %L where id = %L',
    p_date, p_compteur, p_statut, p))
$$;

select coalesce(max(id), 0) as debut from notifications_log \gset

-- ===================================================================
-- X. Personne de confiance avant / après scellage (D-019)
-- ===================================================================
select swend_en_negociation() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select verifier('X', 'Kevin rattaché à son compte dès la création (côté serveur)', (select profil_id from remplacants where id = :'k') = :'K');
select verifier('X', 'avant scellage : Swend non scellé', (select scelle_le from pactes where id = :'p') is null);
select verifier('X', 'avant scellage : Kevin ne voit ni le Swend, ni sa fiche, ni message', vu_par_kevin(:'p') = '0/0/0', vu_par_kevin(:'p'));
select verifier('X', 'avant scellage : Eliot voit toujours sa liste',
  compter_en_tant_que(:'E', format('select count(*) from remplacants where pacte_id = %L', :'p')) = 1);
select verifier('X', 'avant scellage : Kevin ne peut pas écrire à Eliot',
  en_tant_que(:'K', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'k', :'K', 'Coucou')) <> 'OK');
select verifier('X', 'avant scellage : Eliot ne peut pas écrire à Kevin (aucune conversation)',
  en_tant_que(:'E', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'k', :'E', 'Salut')) <> 'OK');
select verifier('X', 'avant scellage : Kevin ne peut pas se déclarer indisponible',
  en_tant_que(:'K', format('select signaler_indisponibilite(%L)', :'k')) like '%swend_inactif%');
select verifier('X', 'avant scellage : Kevin ne peut pas marquer le fil lu',
  en_tant_que(:'K', format('select marquer_fil_lu(%L)', :'k')) like '%Non autorisé%');
select verifier('X', 'avant scellage : Eliot ne peut pas envoyer de demande',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) like '%swend_inactif%');
select en_tant_que(:'E', format('update pactes set scelle_le = now() where id = %L', :'p')) as r \gset
select verifier('X', 'la date de scellage ne peut pas être forcée par l''app', (select scelle_le from pactes where id = :'p') is null, :'r');

select en_tant_que(:'D', format('update pactes set date_retenue = %L, statut = %L where id = %L', '2031-11-10 19:30+00', 'enAttenteReponse', :'p')) as r1 \gset
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'confirme', :'p')) as r2 \gset
select verifier('X', 'David choisit la date A puis accepte', :'r1' = 'OK' and :'r2' = 'OK', :'r1' || ' / ' || :'r2');
select verifier('X', 'scellé : date de scellage posée par la base', (select scelle_le from pactes where id = :'p') is not null);
select verifier('X', 'scellé : Kevin voit le Swend et sa fiche', vu_par_kevin(:'p') = '1/1/0', vu_par_kevin(:'p'));
select verifier('X', 'scellé : Kevin ne voit que sa propre fiche',
  compter_en_tant_que(:'K', format('select count(*) from remplacants where pacte_id = %L and id <> %L', :'p', :'k')) = 0);
select verifier('X', 'scellé : la conversation est ouverte',
  en_tant_que(:'K', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'k', :'K', 'Coucou')) = 'OK');
select en_tant_que(:'K', format('select signaler_indisponibilite(%L)', :'k')) as r1 \gset
select en_tant_que(:'K', format('select signaler_disponibilite(%L)', :'k')) as r2 \gset
select verifier('X', 'scellé : Kevin peut se déclarer indisponible puis disponible (D-008)', :'r1' = 'OK' and :'r2' = 'OK', :'r1' || ' / ' || :'r2');
-- Annulation ultérieure (écriture serveur ; le parcours d'annulation est
-- testé dans 97_annulation_manuelle.sql).
update pactes set statut = 'annule' where id = :'p';
select verifier('X', 'la date de scellage ne bouge plus (annulation ultérieure)', (select scelle_le from pactes where id = :'p') is not null);
-- D-023a : Kevin, seulement prévu, perd l'accès une fois le Swend annulé.
select verifier('X', 'Swend scellé puis annulé : Kevin (seulement prévu) n''a plus accès (D-023a)', vu_par_kevin(:'p') = '0/0/0', vu_par_kevin(:'p'));

-- Refus : Kevin ne voit jamais rien.
select swend_en_negociation() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que(:'D', format('update pactes set date_retenue = %L, statut = %L where id = %L', '2031-11-10 19:30+00', 'enAttenteReponse', :'p')) as r1 \gset
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'annule', :'p')) as r2 \gset
select verifier('X', 'refus : David choisit une date puis refuse', :'r1' = 'OK' and :'r2' = 'OK', :'r1' || ' / ' || :'r2');
select verifier('X', 'refus : jamais scellé, Kevin ne voit rien', (select scelle_le from pactes where id = :'p') is null and vu_par_kevin(:'p') = '0/0/0', vu_par_kevin(:'p'));

-- Kevin prévu des deux côtés (Eliot et David) : rien avant scellage, pour personne.
select swend_en_negociation() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select verifier('X', 'aucune fuite : Camille (autre compte) ne voit rien',
  compter_en_tant_que(:'C', format('select count(*) from pactes where id = %L', :'p')) = 0);
select verifier('X', 'aucune fuite : David ne voit pas la liste d''Eliot',
  compter_en_tant_que(:'D', format('select count(*) from remplacants where pacte_id = %L', :'p')) = 0);

-- ===================================================================
-- N. Négociation de date : au plus 2 contre-propositions au total (D-011)
-- ===================================================================
select swend_en_negociation() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select verifier('N', 'proposition initiale A : aucune contre-proposition', (select nombre_echanges_date from pactes where id = :'p') = 0);
select verifier('N', 'David contre-propose B (n°1)',
  contre_proposer(:'D', :'p', '2031-11-11 19:30+00', 1, 'enAttenteChoixDateInitiateur') = 'OK');
select verifier('N', 'Eliot contre-propose C (n°2)',
  contre_proposer(:'E', :'p', '2031-11-12 19:30+00', 2, 'enAttenteChoixDateDestinataire') = 'OK');
select verifier('N', 'David ne peut pas contre-proposer D (n°3)',
  contre_proposer(:'D', :'p', '2031-11-13 19:30+00', 3, 'enAttenteChoixDateInitiateur') like '%negociation_terminee%');
select verifier('N', 'ni en réutilisant le compteur (dates changées, compteur inchangé)',
  contre_proposer(:'D', :'p', '2031-11-13 19:30+00', 2, 'enAttenteChoixDateInitiateur') like '%negociation_terminee%');
select verifier('N', 'ni en remettant le compteur à zéro',
  contre_proposer(:'D', :'p', '2031-11-13 19:30+00', 0, 'enAttenteChoixDateInitiateur') like '%negociation_terminee%');
select verifier('N', 'les dates restent celles de C',
  (select dates_proposees from pactes where id = :'p') = array['2031-11-12 19:30+00'::timestamptz]);
select en_tant_que(:'D', format('update pactes set date_retenue = %L, statut = %L where id = %L', '2031-11-12 19:30+00', 'enAttenteReponse', :'p')) as r1 \gset
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'confirme', :'p')) as r2 \gset
select verifier('N', 'un accord sur C reste possible (choix puis acceptation)',
  :'r1' = 'OK' and :'r2' = 'OK' and (select scelle_le from pactes where id = :'p') is not null, :'r1' || ' / ' || :'r2');
select verifier('N', 'Swend scellé : plus aucune contre-proposition',
  contre_proposer(:'E', :'p', '2031-11-14 19:30+00', 3, 'enAttenteChoixDateDestinataire') like '%negociation_terminee%');

select swend_en_negociation() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select contre_proposer(:'D', :'p', '2031-11-11 19:30+00', 1, 'enAttenteChoixDateInitiateur') as r1 \gset
select contre_proposer(:'E', :'p', '2031-11-12 19:30+00', 2, 'enAttenteChoixDateDestinataire') as r2 \gset
select contre_proposer(:'D', :'p', '2031-11-13 19:30+00', 3, 'enAttenteChoixDateInitiateur') as r3 \gset
select verifier('N', 'second Swend : B (n°1), C (n°2), puis D refusé',
  :'r1' = 'OK' and :'r2' = 'OK' and :'r3' like '%negociation_terminee%', :'r1' || ' / ' || :'r2' || ' / ' || :'r3');
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'annule', :'p')) as r1 \gset
select verifier('N', 'sans accord, David annule le Swend', :'r1' = 'OK' and (select statut from pactes where id = :'p') = 'annule', :'r1');
select verifier('N', 'négociation échouée : jamais scellé, Kevin ne voit rien',
  (select scelle_le from pactes where id = :'p') is null and vu_par_kevin(:'p') = '0/0/0', vu_par_kevin(:'p'));
select count(*) as avant from pactes where initiateur_id = :'E' \gset
select en_tant_que(:'E', format(
    'insert into pactes (statut, dates_proposees, restaurant_id, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone) values (%L, array[%L::timestamptz], %L, %L, %L, %L, %L)',
    'enAttenteChoixDateDestinataire', '2031-11-20 19:30+00', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', 'David D', '06 00 00 00 02')) as r1 \gset
select verifier('N', 'un nouveau Swend peut être créé ensuite (compteur à zéro, non scellé)',
  :'r1' = 'OK' and (select count(*) from pactes where initiateur_id = :'E') = :avant + 1
  and (select count(*) from pactes where initiateur_id = :'E' and dates_proposees = array['2031-11-20 19:30+00'::timestamptz]
       and nombre_echanges_date = 0 and scelle_le is null) = 1, :'r1');

-- ===================================================================
-- R. Rattrapage des Swends existants (migration)
-- ===================================================================
alter table pactes disable trigger trg_marquer_scellement;
insert into pactes (id, statut, date_retenue, restaurant_id, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone) values
  ('00000000-0000-4000-9000-000000000001', 'confirme', '2031-12-01 19:30+00', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02'),
  ('00000000-0000-4000-9000-000000000002', 'enAttenteReponse', '2031-12-01 19:30+00', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02'),
  ('00000000-0000-4000-9000-000000000003', 'annule', '2031-12-01 19:30+00', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02'),
  ('00000000-0000-4000-9000-000000000004', 'annule', '2031-12-01 19:30+00', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02');
alter table pactes enable trigger trg_marquer_scellement;
select ajouter_fiche(:'D', '00000000-0000-4000-9000-000000000004', 'destinataire', 'Camille', '0600000004') as x \gset
-- Même expression que la ligne de vérification finale de la migration.
create or replace function verification_scellage() returns boolean language sql as $$
  select not exists (select 1 from public.pactes p
               where p.scelle_le is null
                 and (p.statut in ('confirme', 'maintenu', 'annuleDoubleAbsence')
                      or (p.statut = 'annule' and exists (
                            select 1 from public.remplacants r where r.pacte_id = p.id and r.cote = 'destinataire'))))
$$;
select verifier('R', 'avant rattrapage : la vérification finale détecte les Swends scellés sans date (dont l''annulé accepté)',
  not verification_scellage());
select clock_timestamp() as t0 \gset
select rattraper_scellement() as n \gset
select verifier('R', 'rattrapage : scellé = confirmé, ou annulé après acceptation de David',
  (select string_agg(right(id::text, 1) || ':' || (scelle_le is not null), ',' order by id) from pactes
   where id::text like '00000000-0000-4000-9000-%') = '1:true,2:false,3:false,4:true');
select verifier('R', 'rattrapage : valeur de backfill = date d''exécution, pas date_retenue',
  (select bool_and(scelle_le >= :'t0'::timestamptz and scelle_le <= clock_timestamp() and scelle_le <> date_retenue)
   from pactes where id in ('00000000-0000-4000-9000-000000000001', '00000000-0000-4000-9000-000000000004')));
select verifier('R', 'après rattrapage : la vérification finale de la migration est vraie', verification_scellage());

select verifier('X', 'aucune notification à Kevin pendant tout ce fichier',
  (select count(*) from notifications_log where id > :debut and profile_id = :'K') = 0);

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
