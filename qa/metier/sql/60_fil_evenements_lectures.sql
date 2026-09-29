-- Tests de fil_evenements_et_lectures.sql (après 10_scenarios.sql).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set T '00000000-0000-0000-0000-00000000000b'

create or replace function codes(p uuid) returns text language sql as $$
  select coalesce(string_agg(code, ',' order by created_at), '') from evenements_fil where remplacant_id = p
$$;
create or replace function statut(p uuid) returns text language sql as $$
  select coalesce(demande_statut, 'null') from remplacants where id = p
$$;

select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as fk \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as fc \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as ft \gset

-- F1–F2 : demande puis annulation par le titulaire
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'fk')) \gset
select verifier('F1', 'demande envoyée → événement', codes(:'fk') = 'demande_envoyee');
select en_tant_que(:'E', format('select annuler_demande_remplacement(%L)', :'fk')) \gset
select verifier('F2', 'annulée par le titulaire → événement, Kevin redevient sollicitable (D)',
  codes(:'fk') = 'demande_envoyee,demande_annulee' and statut(:'fk') = 'null');

-- F3 : Thomas refuse
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'ft')) \gset
select en_tant_que(:'T', format('select repondre_demande_remplacement(%L, false)', :'ft')) \gset
select verifier('F3', 'refus → événement', codes(:'ft') = 'demande_envoyee,demande_refusee');

-- F4 : demandes à Kevin et Camille, Kevin accepte → Camille clôturée
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'fk')) \gset
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'fc')) \gset
select en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'fk')) \gset
select verifier('F4', 'acceptation → événement', codes(:'fk') = 'demande_envoyee,demande_annulee,demande_envoyee,demande_acceptee');
select verifier('F4', 'clôture automatique de Camille → événement', codes(:'fc') = 'demande_envoyee,demande_cloturee');

-- F5 : Kevin se désiste
select en_tant_que(:'K', format('select se_desister_du_remplacement(%L)', :'fk')) \gset
select verifier('F5', 'désistement → événement', codes(:'fk') like '%,desistement');
select verifier('F5', 'B : Kevin reste indisponible (desistee)', statut(:'fk') = 'desistee');
select verifier('F5', 'A : Thomas reste indisponible (refusee)', statut(:'ft') = 'refusee');
select verifier('F5', 'C : Camille redevient sollicitable, sans nouvelle demande', statut(:'fc') = 'null');
select verifier('F5', 'C : aucun événement pour la réouverture de Camille', codes(:'fc') = 'demande_envoyee,demande_cloturee');

-- F6 : qui voit quoi
select verifier('F6', 'Eliot voit les événements de ses 3 fiches',
  compter_en_tant_que(:'E', format('select count(distinct e.remplacant_id) from evenements_fil e join remplacants r on r.id = e.remplacant_id where r.pacte_id = %L', :'p')) = 3);
select verifier('F6', 'Kevin ne voit que son fil',
  compter_en_tant_que(:'K', format('select count(*) from evenements_fil where remplacant_id in (select id from remplacants where pacte_id = %L) and remplacant_id <> %L', :'p', :'fk')) = 0
  and compter_en_tant_que(:'K', format('select count(*) from evenements_fil where remplacant_id = %L', :'fk')) = 5);
select verifier('F6', 'David ne voit aucun événement du côté d''Eliot',
  compter_en_tant_que(:'D', format('select count(*) from evenements_fil where remplacant_id in (%L, %L, %L)', :'fk', :'fc', :'ft')) = 0
  and (select count(*) from evenements_fil where remplacant_id in (:'fk', :'fc', :'ft')) = 9);
select verifier('F6', 'écriture directe d''un événement refusée',
  en_tant_que(:'E', format('insert into evenements_fil (remplacant_id, code) values (%L, %L)', :'fk', 'demande_envoyee')) like 'permission denied%');

-- F7 : lu / non lu
select verifier('F7', 'Kevin marque son fil lu',
  en_tant_que(:'K', format('select marquer_fil_lu(%L)', :'fk')) = 'OK');
select verifier('F7', 'Eliot marque le fil de Kevin lu',
  en_tant_que(:'E', format('select marquer_fil_lu(%L)', :'fk')) = 'OK');
select verifier('F7', 'David ne peut pas (fil de l''autre côté)',
  en_tant_que(:'D', format('select marquer_fil_lu(%L)', :'fk')) like '%Non autorisé%');
select verifier('F7', 'Camille ne peut pas marquer le fil de Kevin',
  en_tant_que(:'C', format('select marquer_fil_lu(%L)', :'fk')) like '%Non autorisé%');
select verifier('F7', 'chacun ne lit que ses propres lectures',
  compter_en_tant_que(:'K', 'select count(*) from lectures_fil') = 1
  and compter_en_tant_que(:'E', 'select count(*) from lectures_fil') = 1
  and compter_en_tant_que(:'D', 'select count(*) from lectures_fil') = 0
  and (select count(*) from lectures_fil) = 2);
select verifier('F7', 'écriture directe d''une lecture refusée',
  en_tant_que(:'K', format('insert into lectures_fil (remplacant_id, profile_id) values (%L, %L)', :'fk', :'K')) like 'permission denied%');

-- F8 : ajouter et demander (pendant l'imprévu) → événement
select en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'Zoé', 'Z', '0600000006')) \gset
select verifier('F8', 'ajout + demande → événement demande_envoyee',
  (select codes(id) from remplacants where pacte_id = :'p' and prenom = 'Zoé') = 'demande_envoyee');

-- F9 : retirer une personne ne détruit rien (D-023a) : fiche archivée,
-- événements conservés en base, plus visibles pour Thomas.
select count(*) as nev_ft from evenements_fil where remplacant_id = :'ft' \gset
select en_tant_que(:'E', format('select retirer_remplacant(%L)', :'ft')) \gset
select verifier('F9', 'retrait de Thomas → fiche archivée, ses événements conservés',
  (select retire_le is not null from remplacants where id = :'ft')
  and (select count(*) from evenements_fil where remplacant_id = :'ft') = :nev_ft and :nev_ft > 0);

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
