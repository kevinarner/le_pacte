-- Tests du chantier téléphone (phase 2), après 10_scenarios.sql (qui
-- définit les outils : en_tant_que, verifier, ajouter_fiche, nouveau_swend).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
-- Cette suite crée plusieurs Swends Eliot ↔ David au nom des utilisateurs :
-- la règle « un Swend en cours par paire » (D-023c, testée par
-- 99e_nouveau_swend.sql) est suspendue le temps de la suite, puis rétablie.
alter table pactes disable trigger trg_verrou_un_swend_par_paire;

\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set KA '00000000-0000-0000-0000-0000000000a1'
\set ZR '00000000-0000-0000-0000-0000000000f5'

-- Kevin s'est inscrit avec "0670419277" ; Zoé (Réunion) avec "0692 12 34 56".
insert into profiles (id, prenom, nom, telephone) values
  (:'KA', 'Kevin', 'Arner', '0670419277'),
  (:'ZR', 'Zoé', 'Réunion', '0692 12 34 56')
on conflict do nothing;

-- Essaie une commande en postgres et renvoie l'erreur éventuelle.
create or replace function essayer(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end $$;

-- T1. Le cas du point 6 ---------------------------------------------------
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '06 70 41 92 77') as ke \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '+33670419277') as kd \gset
select verifier('T1', 'Eliot saisit "06 70 41 92 77" → fiche liée au compte de Kevin',
  (select profil_id from remplacants where id = :'ke') = :'KA');
select verifier('T1', 'David saisit "+33670419277" → même compte',
  (select profil_id from remplacants where id = :'kd') = :'KA');
select en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'ke')) as r \gset
select verifier('T1', 'Kevin accepte la place d''Eliot',
  en_tant_que(:'KA', format('select repondre_demande_remplacement(%L, true)', :'ke')) = 'OK');
select verifier('T1', 'Kevin devient "Indisponible" côté David', statut_fiche(:'kd') = 'cloturee', statut_fiche(:'kd'));
select verifier('T1', 'David ne peut pas le solliciter',
  en_tant_que(:'D', format('select envoyer_demande_remplacement(%L)', :'kd')) like '%personne_indisponible%');

-- T2. Personne sans compte, qui s'inscrit ensuite sous un autre format ---
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Léo', '07 12 34 56 78') as le \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Léo', '+33 7 12 34 56 78') as ld \gset
select verifier('T2', 'avant inscription : aucune des deux fiches liée',
  (select count(profil_id) from remplacants where id in (:'le', :'ld')) = 0);
select en_tant_que(:'E', format(
  'insert into pactes (statut, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone) values (%L, %L, %L, %L, %L)',
  'enAttenteChoixDateDestinataire', :'E', 'Eliot E', 'Mia', '07.12.34.56.79')) as r \gset
select id as pm from pactes where destinataire_nom = 'Mia' \gset
select verifier('T2', 'Swend proposé à Mia (sans compte) : destinataire non lié', (select destinataire_id from pactes where id = :'pm') is null);
-- Inscription (handle_new_user insère le profil)
insert into profiles (id, prenom, nom, telephone) values
  ('00000000-0000-0000-0000-0000000000b1', 'Léo', 'L', '0033 7 12 34 56 78'),
  ('00000000-0000-0000-0000-0000000000b2', 'Mia', 'M', '+33712345679');
select verifier('T2', 'à l''inscription de Léo ("0033 …") : ses deux fiches sont liées',
  (select count(*) from remplacants where id in (:'le', :'ld') and profil_id = '00000000-0000-0000-0000-0000000000b1') = 2);
select verifier('T2', 'à l''inscription de Mia ("+33…") : le Swend lui est rattaché',
  (select destinataire_id from pactes where id = :'pm') = '00000000-0000-0000-0000-0000000000b2');

-- T3. Unicité canonique des comptes --------------------------------------
select verifier('T3', 'deuxième compte avec le numéro de Kevin sous un autre format : refusé',
  essayer($$insert into profiles (id, prenom, nom, telephone) values ('00000000-0000-0000-0000-0000000000c9', 'Faux', 'Kevin', '+33 6 70 41 92 77')$$) like '%profiles_telephone_e164_unique%');
select verifier('T3', 'numéro de compte invalide (fixe) : refusé',
  essayer($$insert into profiles (id, prenom, nom, telephone) values ('00000000-0000-0000-0000-0000000000c8', 'Fixe', 'X', '01 23 45 67 89')$$) like '%telephone_invalide%');
select verifier('T3', 'numéro de compte "0000" : refusé',
  essayer($$insert into profiles (id, prenom, nom, telephone) values ('00000000-0000-0000-0000-0000000000c7', 'Zero', 'X', '0000')$$) like '%telephone_invalide%');

-- T4. Même personne deux fois du même côté --------------------------------
select nouveau_swend() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0670419277') as k1 \gset
select verifier('T4', 'Kevin re-saisi sous un autre format du même côté : refusé',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'initiateur', 'Kev', 'A', '+33 6 70 41 92 77', '')) like '%personne_deja_prevue%');
select verifier('T4', 'même refus via "Ajouter quelqu''un", rien inséré',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'Kev', 'A', '0033670419277')) like '%personne_deja_prevue%'
  and (select count(*) from remplacants where pacte_id = :'p') = 1);
select verifier('T4', 'la même personne reste possible de l''autre côté',
  en_tant_que(:'D', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'destinataire', 'Kevin', 'A', '+33670419277', '')) = 'OK');

-- T5. Un participant du Swend ne peut pas être personne de confiance ----
select nouveau_swend() as p \gset
select verifier('T5', 'Eliot ajoute David (numéro sous un autre format) : refusé',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'initiateur', 'David', 'D', '+33 6 00 00 00 02', '')) like '%personne_est_participant%');
select verifier('T5', 'Eliot s''ajoute lui-même : refusé',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'initiateur', 'Eliot', 'E', '06 00 00 00 01', '')) like '%personne_est_participant%');
select verifier('T5', 'David ajoute Eliot : refusé',
  en_tant_que(:'D', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'destinataire', 'Eliot', 'E', '0600000001', '')) like '%personne_est_participant%');
select verifier('T5', 'via "Ajouter quelqu''un" : refusé, rien inséré',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'David', 'D', '0600000002')) like '%personne_est_participant%'
  and (select count(*) from remplacants where pacte_id = :'p') = 0);
select en_tant_que(:'E', format(
  'insert into pactes (statut, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone) values (%L, %L, %L, %L, %L)',
  'enAttenteChoixDateDestinataire', :'E', 'Eliot E', 'Noé', '07 99 88 77 66')) as r \gset
select id as pn from pactes where destinataire_nom = 'Noé' \gset
select verifier('T5', 'destinataire sans compte ajouté comme personne de confiance : refusé',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'pn', 'initiateur', 'Noé', 'N', '+33799887766', '')) like '%personne_est_participant%');

-- T6. destinataire_id jamais repris du client -----------------------------
select en_tant_que(:'E', format(
    'insert into pactes (statut, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone) values (%L, %L, %L, %L, %L, %L)',
    'enAttenteChoixDateDestinataire', :'E', 'Eliot E', :'KA', 'Faux1', '+33 6 00 00 00 02')) as r1 \gset
select verifier('T6', 'destinataire_id falsifié (Kevin) pour un numéro de David : corrigé en David',
  :'r1' = 'OK' and (select destinataire_id from pactes where destinataire_nom = 'Faux1') = :'D', :'r1');
select en_tant_que(:'E', format(
    'insert into pactes (statut, initiateur_id, initiateur_nom, destinataire_id, destinataire_nom, destinataire_telephone) values (%L, %L, %L, %L, %L, %L)',
    'enAttenteChoixDateDestinataire', :'E', 'Eliot E', :'KA', 'Faux2', '07 55 44 33 22')) as r2 \gset
select verifier('T6', 'destinataire_id falsifié pour un numéro sans compte : ignoré (vide)',
  :'r2' = 'OK' and exists (select 1 from pactes where destinataire_nom = 'Faux2' and destinataire_id is null), :'r2');
select verifier('T6', 'Swend avec soi-même (autre format) : refusé',
  en_tant_que(:'E', format(
    'insert into pactes (statut, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone) values (%L, %L, %L, %L, %L)',
    'enAttenteChoixDateDestinataire', :'E', 'Eliot E', 'Moi', '+33600000001')) like '%destinataire_est_initiateur%');
select verifier('T6', 'Swend vers un numéro invalide : refusé',
  en_tant_que(:'E', format(
    'insert into pactes (statut, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone) values (%L, %L, %L, %L, %L)',
    'enAttenteChoixDateDestinataire', :'E', 'Eliot E', 'Zéro', '0000')) like '%telephone_invalide%');
select id as pf from pactes where destinataire_nom = 'Faux2' \gset
select verifier('T6', 'l''initiateur ne peut pas changer le destinataire ensuite',
  en_tant_que(:'E', format('update pactes set destinataire_id = %L where id = %L', :'KA', :'pf')) like '%modification_interdite%');
select verifier('T6', '... ni son numéro',
  en_tant_que(:'E', format('update pactes set destinataire_telephone = %L where id = %L', '0612345678', :'pf')) like '%modification_interdite%');
select verifier('T6', 'les mises à jour normales (statut) restent possibles',
  en_tant_que(:'E', format('update pactes set statut = %L where id = %L', 'annule', :'pf')) = 'OK');

-- T7. Numéro de compte figé ------------------------------------------------
select verifier('T7', 'Kevin ne peut pas changer son numéro depuis l''app',
  en_tant_que(:'KA', format('update profiles set telephone = %L where id = %L', '0612345678', :'KA')) like '%telephone_fige%');
select verifier('T7', 'les autres champs du profil restent modifiables',
  en_tant_que(:'KA', format('update profiles set nom = %L where id = %L', 'Arner', :'KA')) = 'OK');
select verifier('T7', 'intervention manuelle (SQL Editor) possible, avec numéro valide',
  essayer(format('update profiles set telephone = %L where id = %L', '+33 6 70 41 92 77', :'KA')) = 'OK'
  and (select telephone_e164 from profiles where id = :'KA') = '+33670419277');

-- T8. Plus de recherche de compte par numéro depuis l'app ------------------
select verifier('T8', 'trouver_profil_par_telephone interdite au rôle authenticated',
  en_tant_que(:'E', $$select trouver_profil_par_telephone('0670419277')$$) like '%permission denied%');

-- T9. Numéro de personne de confiance invalide ----------------------------
select nouveau_swend() as p \gset
select verifier('T9', '"0000" : refusé',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'initiateur', 't', 't', '0000', '')) like '%telephone_invalide%');
select verifier('T9', 'fixe "01 23 45 67 89" : refusé',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'initiateur', 'Fixe', 'F', '01 23 45 67 89', '')) like '%telephone_invalide%');
select verifier('T9', '"Ajouter quelqu''un" avec "06 12" : refusé, rien inséré',
  en_tant_que(:'E', format('select ajouter_et_demander_remplacement(%L, %L, %L, %L, %L)', :'p', 'initiateur', 'X', 'Y', '06 12')) like '%telephone_invalide%'
  and (select count(*) from remplacants where pacte_id = :'p') = 0);
select verifier('T9', 'numéro étranger avec indicatif : accepté',
  en_tant_que(:'E', format('insert into remplacants (pacte_id, cote, prenom, nom, telephone, email) values (%L, %L, %L, %L, %L, %L)',
    :'p', 'initiateur', 'Tom', 'UK', '+44 7911 123456', '')) = 'OK');

-- T10. Outre-mer ------------------------------------------------------------
select ajouter_fiche(:'E', :'p', 'initiateur', 'Zoé', '+33 692 12 34 56') as zf \gset
select verifier('T10', 'Zoé (inscrite "0692 12 34 56") saisie "+33 692 12 34 56" : reconnue',
  (select profil_id from remplacants where id = :'zf') = :'ZR');

alter table pactes enable trigger trg_verrou_un_swend_par_paire;
select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail
from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
