-- Suivi interne des réservations manuelles V1 (D-020) : création au
-- scellage, rattrapage, annulation, suppression, vue, aucun accès pour l'app.
-- Utilise les outils de 10_imprevu.sql (verifier, en_tant_que) et
-- swend_en_negociation() de 90_scellage_negociation.sql.
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'

-- Exécute une commande sous un rôle de l'app (anon, authenticated) ; 'OK' ou l'erreur.
create or replace function en_tant_que_role(p_role text, p_user uuid, p_sql text) returns text
language plpgsql as $$
declare v_res text := 'OK';
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
  exception when others then
    v_res := sqlerrm;
  end;
  execute 'reset role';
  return v_res;
end $$;
create or replace function nb_suivis(p uuid) returns int language sql as $$
  select count(*)::int from reservations_suivi where pacte_id = p
$$;
-- Scelle un Swend en négociation comme l'app : David choisit la première des
-- dates proposées (D-025b) puis accepte.
create or replace function sceller(p uuid) returns void language plpgsql as $$
begin
  if en_tant_que('00000000-0000-0000-0000-00000000000d', format('update pactes set date_retenue = %L, statut = %L where id = %L',
       (select (instants_proposes(dates_proposees))[1] from pactes where id = p), 'enAttenteReponse', p)) <> 'OK' then
    raise exception 'choix de date impossible';
  end if;
  if en_tant_que('00000000-0000-0000-0000-00000000000d', format('update pactes set statut = %L where id = %L', 'confirme', p)) <> 'OK' then
    raise exception 'acceptation impossible';
  end if;
end $$;

-- ===================================================================
-- C. Création automatique au scellage
-- ===================================================================
select swend_en_negociation() as p \gset
select verifier('C', 'Swend non scellé : aucune ligne de suivi', nb_suivis(:'p') = 0);
select sceller(:'p');
select verifier('C', 'au scellage : une ligne créée, statut a_reserver',
  nb_suivis(:'p') = 1 and (select statut_reservation from reservations_suivi where pacte_id = :'p') = 'a_reserver');
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'confirme', :'p')) as r \gset
select verifier('C', 'nouvelle mise à jour du Swend scellé : toujours une seule ligne', nb_suivis(:'p') = 1, :'r');
-- Rejeu du mécanisme : scelle_le repasse par null puis non-null.
select set_config('swend.rattrapage_scellement', 'on', false) as x \gset
update pactes set scelle_le = null where id = :'p';
update pactes set scelle_le = now() where id = :'p';
select set_config('swend.rattrapage_scellement', 'off', false) as x \gset
select verifier('C', 'déclencheur rejoué (null → scellé une seconde fois) : pas de doublon', nb_suivis(:'p') = 1);
select verifier('C', 'rattrapage rejoué sur un Swend déjà suivi : aucune ligne ajoutée',
  rattraper_reservations_suivi() = 0 and nb_suivis(:'p') = 1);
\set p_actif :p

-- ===================================================================
-- V. Vue : les champs correspondent au bon Swend
-- ===================================================================
update reservations_suivi set pris_en_charge_par = 'Eliot', nom_reservation = 'Martin', reference_reservation = 'R-42', note = 'table en terrasse'
where pacte_id = :'p_actif';
select verifier('V', 'Swend à réserver : a_faire = Réserver, champs du bon Swend',
  (select v.a_faire = 'Réserver' and v.swend_id = :'p_actif' and v.statut_swend = 'confirme'
      and v.initiateur = 'Eliot E' and v.destinataire = 'David D' and v.destinataire_telephone = '06 00 00 00 02'
      and v.initiateur_telephone = '0600000001' and v.restaurant = 'Au Père Lapin'
      and v.date_rdv = (p.date_retenue at time zone 'Europe/Paris')::date
      and v.heure_rdv = to_char(p.date_retenue at time zone 'Europe/Paris', 'HH24:MI')
      and v.scelle_le = p.scelle_le
      and v.statut_reservation = 'a_reserver' and v.pris_en_charge_par = 'Eliot' and v.nom_reservation = 'Martin'
      and v.reference_reservation = 'R-42' and v.note = 'table en terrasse'
   from reservations_a_suivre v join pactes p on p.id = v.swend_id where v.swend_id = :'p_actif'));
select verifier('V', 'derniere_modification suit la dernière mise à jour',
  (select v.derniere_modification >= s.created_at from reservations_a_suivre v join reservations_suivi s on s.id = v.suivi_id
   where v.swend_id = :'p_actif'));
update reservations_suivi set statut_reservation = 'reservee' where pacte_id = :'p_actif';
select verifier('V', 'Swend actif réservé : plus rien à faire',
  (select a_faire = '' from reservations_a_suivre where swend_id = :'p_actif'));
update reservations_suivi set statut_reservation = 'probleme' where pacte_id = :'p_actif';
select verifier('V', 'Swend actif en problème : contacter les participants',
  (select a_faire = 'Problème : contacter les participants' from reservations_a_suivre where swend_id = :'p_actif'));
select verifier('V', 'statut de réservation hors liste refusé (pas de « réservation en cours »)',
  en_tant_que_role('postgres', null, format('update reservations_suivi set statut_reservation = %L where pacte_id = %L', 'en_cours', :'p_actif'))
    like '%violates check constraint%');

-- ===================================================================
-- A. Annulation du Swend : le statut de réservation ne change pas
-- ===================================================================
select swend_en_negociation() as p \gset
select sceller(:'p');
update reservations_suivi set statut_reservation = 'reservee', reference_reservation = 'R-7' where pacte_id = :'p';
select en_tant_que(:'E', format('select annuler_swend(%L)', :'p')) as r \gset
select verifier('A', 'Swend annulé : statut de réservation inchangé (reservee)',
  :'r' = 'OK' and (select statut_reservation from reservations_suivi where pacte_id = :'p') = 'reservee', :'r');
select verifier('A', 'Swend annulé + réservé : identifiable dans la vue, à annuler au restaurant',
  (select statut_swend = 'annule' and statut_reservation = 'reservee' and reference_reservation = 'R-7'
      and a_faire = 'Annuler la réservation au restaurant'
   from reservations_a_suivre where swend_id = :'p'));
select verifier('A', 'les actions à mener apparaissent en tête de la vue',
  (select bool_and(a_faire <> '') from (select a_faire from reservations_a_suivre limit 2) x));
select swend_en_negociation() as p2 \gset
select sceller(:'p2');
select en_tant_que(:'E', format('select annuler_swend(%L)', :'p2')) as r \gset
select verifier('A', 'Swend annulé non réservé : a_reserver conservé, aucune action',
  (select statut_reservation = 'a_reserver' and a_faire = '' from reservations_a_suivre where swend_id = :'p2'));

-- ===================================================================
-- S. Swend scellé supprimé (en interne) : la ligne de suivi est conservée
-- ===================================================================
select swend_en_negociation() as p \gset
select sceller(:'p');
update reservations_suivi set statut_reservation = 'reservee' where pacte_id = :'p';
select id as suivi from reservations_suivi where pacte_id = :'p' \gset
select en_tant_que(:'E', format('select supprimer_pacte(%L)', :'p')) as r \gset
select verifier('S', 'Swend scellé : Eliot ne peut pas le supprimer depuis l''app (D-022)', :'r' like '%swend_scelle%' and exists (select 1 from pactes where id = :'p'), :'r');
delete from pactes where id = :'p';
select verifier('S', 'suppression interne (hors app)', not exists (select 1 from pactes where id = :'p'));
select verifier('S', 'ligne de suivi conservée, statut reservee, résumé du Swend',
  (select pacte_id is null and statut_reservation = 'reservee' and swend_supprime_le is not null
      and resume_swend_supprime like 'Eliot E / David D — Au Père Lapin — %'
   from reservations_suivi where id = :'suivi'));
select verifier('S', 'vue : Swend supprimé réservé, à annuler au restaurant',
  (select statut_swend = 'supprimé' and a_faire = 'Annuler la réservation au restaurant' and resume_swend_supprime is not null
   from reservations_a_suivre where suivi_id = :'suivi'));

-- ===================================================================
-- R. Rattrapage des Swends déjà scellés
-- ===================================================================
alter table pactes disable trigger trg_creer_suivi_reservation_insert;
insert into pactes (id, statut, date_retenue, restaurant_id, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone) values
  ('00000000-0000-4000-9500-000000000001', 'confirme', now() + interval '10 days', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02'),
  ('00000000-0000-4000-9500-000000000002', 'confirme', now() - interval '10 days', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02'),
  ('00000000-0000-4000-9500-000000000003', 'confirme', now() + interval '12 days', '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02'),
  ('00000000-0000-4000-9500-000000000004', 'enAttenteChoixDateDestinataire', null, '00000000-0000-0000-0000-0000000000aa', :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02');
alter table pactes enable trigger trg_creer_suivi_reservation_insert;
insert into reservations_suivi (pacte_id, statut_reservation, note) values ('00000000-0000-4000-9500-000000000003', 'reservee', 'déjà suivi');
select verifier('R', 'avant rattrapage : Swends scellés sans ligne de suivi',
  (select count(*) from pactes p where p.scelle_le is not null and not exists (select 1 from reservations_suivi s where s.pacte_id = p.id)) = 2);
select verifier('R', 'rattrapage : crée exactement les 2 lignes manquantes', rattraper_reservations_suivi() = 2);
select verifier('R', 'rattrapage : lignes créées en a_reserver, ligne existante intacte, Swend non scellé ignoré',
  (select string_agg(right(pacte_id::text, 1) || ':' || statut_reservation || ':' || coalesce(note, '-'), ',' order by pacte_id)
   from reservations_suivi where pacte_id::text like '00000000-0000-4000-9500-%') = '1:a_reserver:-,2:a_reserver:-,3:reservee:déjà suivi');
select verifier('R', 'rattrapage rejoué : aucune ligne', rattraper_reservations_suivi() = 0);
select verifier('R', 'Swend passé rattrapé : aucune action affichée',
  (select a_faire = '' from reservations_a_suivre where swend_id = '00000000-0000-4000-9500-000000000002'));
select verifier('R', 'invariant : chaque Swend scellé a exactement une ligne',
  not exists (select 1 from pactes p where p.scelle_le is not null
    and (select count(*) from reservations_suivi s where s.pacte_id = p.id) <> 1));

-- ===================================================================
-- P. Aucun accès pour l'application (anon, authenticated)
-- ===================================================================
select verifier('P', 'anon ne lit pas la table',
  en_tant_que_role('anon', null, 'select count(*) from reservations_suivi') like '%permission denied%');
select verifier('P', 'anon n''écrit pas dans la table',
  en_tant_que_role('anon', null, format('insert into reservations_suivi (pacte_id) values (%L)', :'p2')) like '%permission denied%');
select verifier('P', 'authenticated (Eliot) ne lit pas la table',
  en_tant_que_role('authenticated', :'E', 'select count(*) from reservations_suivi') like '%permission denied%');
select verifier('P', 'authenticated n''insère pas',
  en_tant_que_role('authenticated', :'E', format('insert into reservations_suivi (pacte_id) values (%L)', :'p2')) like '%permission denied%');
select verifier('P', 'authenticated ne modifie pas',
  en_tant_que_role('authenticated', :'E', 'update reservations_suivi set statut_reservation = ''annulee''') like '%permission denied%');
select verifier('P', 'authenticated ne supprime pas',
  en_tant_que_role('authenticated', :'E', 'delete from reservations_suivi') like '%permission denied%');
select verifier('P', 'anon ne lit pas la vue',
  en_tant_que_role('anon', null, 'select count(*) from reservations_a_suivre') like '%permission denied%');
select verifier('P', 'authenticated ne lit pas la vue',
  en_tant_que_role('authenticated', :'E', 'select count(*) from reservations_a_suivre') like '%permission denied%');
select verifier('P', 'authenticated ne peut pas lancer le rattrapage',
  en_tant_que_role('authenticated', :'E', 'select rattraper_reservations_suivi()') like '%permission denied%');
select verifier('P', 'aucun droit accordé aux rôles de l''app (table et vue)',
  not has_table_privilege('anon', 'reservations_suivi', 'select, insert, update, delete, truncate, references, trigger')
  and not has_table_privilege('authenticated', 'reservations_suivi', 'select, insert, update, delete, truncate, references, trigger')
  and not has_table_privilege('anon', 'reservations_a_suivre', 'select, insert, update, delete')
  and not has_table_privilege('authenticated', 'reservations_a_suivre', 'select, insert, update, delete'));
select verifier('P', 'RLS activée sur la table',
  (select relrowsecurity from pg_class where oid = 'reservations_suivi'::regclass));
select verifier('P', 'le scellage par un utilisateur de l''app crée quand même la ligne (fonction serveur)',
  nb_suivis(:'p_actif') = 1);

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
