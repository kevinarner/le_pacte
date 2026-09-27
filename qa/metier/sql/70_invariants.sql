-- Invariants transverses (après 10_imprevu.sql, qui définit les outils :
-- verifier, en_tant_que, compter_en_tant_que, nouveau_swend, ajouter_fiche).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'

-- N. Normalisation des numéros (même règle que lib/utils/telephone.dart) --
select verifier('N', '"06 70 41 92 77" → +33670419277', normaliser_telephone('06 70 41 92 77') = '+33670419277');
select verifier('N', '"07.11.22.33.44" → +33711223344', normaliser_telephone('07.11.22.33.44') = '+33711223344');
select verifier('N', '"+33 6 70 41 92 77" → +33670419277', normaliser_telephone('+33 6 70 41 92 77') = '+33670419277');
select verifier('N', '"0033 6 70 41 92 77" → +33670419277', normaliser_telephone('0033 6 70 41 92 77') = '+33670419277');
select verifier('N', '"+33 (0)6 70 41 92 77" → +33670419277', normaliser_telephone('+33 (0)6 70 41 92 77') = '+33670419277');
select verifier('N', 'E.164 déjà canonique inchangé', normaliser_telephone('+33670419277') = '+33670419277');
select verifier('N', 'outre-mer "0692 12 34 56" → +262692123456', normaliser_telephone('0692 12 34 56') = '+262692123456');
select verifier('N', 'étranger "+44 7911 123456" accepté', normaliser_telephone('+44 7911 123456') = '+447911123456');
select verifier('N', 'fixe "01 23 45 67 89" refusé', normaliser_telephone('01 23 45 67 89') is null);
select verifier('N', 'trop court "06 70 41" refusé', normaliser_telephone('06 70 41') is null);
select verifier('N', 'lettres refusées', normaliser_telephone('06 AB CD EF GH') is null);
select verifier('N', 'vide refusé', normaliser_telephone('') is null);

-- M. Confidentialité des messages ------------------------------------------
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as fk \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as fc \gset
select verifier('M', 'Kevin écrit dans son fil',
  en_tant_que(:'K', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'fk', :'K', 'Coucou Eliot')) = 'OK');
select verifier('M', 'Eliot écrit dans le fil de Kevin',
  en_tant_que(:'E', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'fk', :'E', 'Salut Kevin')) = 'OK');
select verifier('M', 'Kevin lit les 2 messages de son fil',
  compter_en_tant_que(:'K', format('select count(*) from messages where remplacant_id = %L', :'fk')) = 2);
select verifier('M', 'David ne lit aucun message du côté d''Eliot',
  compter_en_tant_que(:'D', format('select count(*) from messages where remplacant_id in (%L, %L)', :'fk', :'fc')) = 0);
select verifier('M', 'Camille ne lit pas le fil de Kevin',
  compter_en_tant_que(:'C', format('select count(*) from messages where remplacant_id = %L', :'fk')) = 0);
select verifier('M', 'David ne peut pas écrire dans le fil de Kevin',
  en_tant_que(:'D', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'fk', :'D', 'intrusion')) <> 'OK');
select verifier('M', 'personne ne peut écrire au nom d''un autre',
  en_tant_que(:'K', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'fk', :'E', 'usurpation')) <> 'OK');

-- R. Droits d'une personne de confiance (tiers) ---------------------------
select verifier('R', 'Kevin (tiers) voit le Swend concerné',
  compter_en_tant_que(:'K', format('select count(*) from pactes where id = %L', :'p')) = 1);
select verifier('R', 'Kevin ne voit que sa propre fiche du côté d''Eliot',
  compter_en_tant_que(:'K', format('select count(*) from remplacants where pacte_id = %L', :'p')) = 1);
select en_tant_que(:'K', format('update pactes set statut = %L where id = %L', 'annule', :'p')) \gset
select verifier('R', 'Kevin ne peut pas modifier le Swend', (select statut from pactes where id = :'p') = 'confirme');
select verifier('R', 'Kevin ne peut pas ajouter de personne côté Eliot',
  en_tant_que(:'K', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)', :'p', 'initiateur', 'Intrus', 'X', '0612345678', '')) <> 'OK');
select verifier('R', 'Kevin ne peut pas envoyer de demande (réservé au titulaire)',
  en_tant_que(:'K', format('select envoyer_demande_remplacement(%L)', :'fc')) <> 'OK');
select verifier('R', 'Kevin ne peut pas répondre à la place de Camille',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'fc')) = 'OK'
  and en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'fc')) <> 'OK');
select verifier('R', 'un inconnu (David) ne voit pas la fiche de Kevin',
  compter_en_tant_que(:'D', format('select count(*) from remplacants where id = %L', :'fk')) = 0);

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
