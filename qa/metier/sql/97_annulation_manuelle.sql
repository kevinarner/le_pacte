-- Annulation manuelle d'un Swend scellé (D-022). Déterministe : Swends
-- datés du lundi 13 octobre 2031 à 20h00 (Paris), bien après l'horloge
-- réelle ; seule la vérification « après l'heure » utilise un Swend passé.
-- Utilise les outils de 10_imprevu.sql (verifier, en_tant_que, ajouter_fiche).
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;
\set E '00000000-0000-0000-0000-00000000000e'
\set D '00000000-0000-0000-0000-00000000000d'
\set K '00000000-0000-0000-0000-00000000000a'
\set C '00000000-0000-0000-0000-00000000000c'
\set T '00000000-0000-0000-0000-00000000000b'
\set Z '00000000-0000-0000-0000-00000000000f'

-- Swend scellé Eliot (initiateur) / David (destinataire).
create or replace function swend_annulable(p_date timestamptz default '2031-10-13 18:00+00')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, type, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
                      destinataire_id, destinataire_nom, destinataire_telephone)
  values ('confirme', 'diner', p_date, '00000000-0000-0000-0000-0000000000aa',
          '00000000-0000-0000-0000-00000000000e', 'Eliot E',
          '00000000-0000-0000-0000-00000000000d', 'David D', '06 00 00 00 02')
  returning id into v;
  return v;
end $$;
-- Push reçues par une personne depuis n0 : « titre|corps » dans l'ordre.
create or replace function push_annul(p_n0 bigint, p_profil uuid) returns text language sql as $$
  select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '')
  from notifications_log where id > p_n0 and profile_id = p_profil
$$;
create or replace function d22_nb_push(p_n0 bigint) returns int language sql as $$
  select count(*)::int from notifications_log where id > p_n0
$$;
create or replace function d22_demander(p_titulaire uuid, p_fiche uuid) returns void language plpgsql as $$
begin
  if en_tant_que(p_titulaire, format('select envoyer_demande_remplacement(%L)', p_fiche)) <> 'OK' then
    raise exception 'demande impossible';
  end if;
end $$;
create or replace function d22_accepter(p_personne uuid, p_fiche uuid) returns void language plpgsql as $$
begin
  if en_tant_que(p_personne, format('select repondre_demande_remplacement(%L, true)', p_fiche)) <> 'OK' then
    raise exception 'acceptation impossible';
  end if;
end $$;
create or replace function d22_annuler(p_user uuid, p uuid) returns text language sql as $$
  select en_tant_que(p_user, format('select annuler_swend(%L)', p))
$$;
create or replace function d22_statut(p uuid) returns text language sql as $$
  select statut from pactes where id = p
$$;

select verifier('T', 'date de référence : lundi 13 octobre à 20h00 (Paris)',
  date_rappel_fr('2031-10-13 18:00+00') || ' à ' || heure_rappel_fr('2031-10-13 18:00+00') = 'lundi 13 octobre à 20h00');

-- ===================================================================
-- N. Swend normal : Eliot annule, David prévenu, Kevin (prévu) rien
-- ===================================================================
select swend_annulable() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('N', 'Kevin (personne de confiance) ne peut pas annuler', d22_annuler(:'K', :'p') like '%non_autorise%', d22_annuler(:'K', :'p'));
select verifier('N', 'un inconnu ne peut pas annuler', d22_annuler(:'Z', :'p') like '%non_autorise%');
select verifier('N', 'le Swend est toujours scellé', d22_statut(:'p') = 'confirme');
select verifier('N', 'Eliot annule', d22_annuler(:'E', :'p') = 'OK');
select verifier('N', 'Swend annulé immédiatement', d22_statut(:'p') = 'annule');
select verifier('N', 'David : push validée, sans motif',
  push_annul(:n0, :'D') = 'Ton Swend est annulé|Eliot a annulé votre Swend du lundi 13 octobre à 20h00 · Au Père Lapin.',
  push_annul(:n0, :'D'));
select verifier('N', 'push de David : ouvre la fiche du Swend',
  (select data = jsonb_build_object('type', 'pacte', 'pacte_id', :'p') from notifications_log where id > :n0 and profile_id = :'D'));
select verifier('N', 'Kevin (seulement prévu) : aucune push, fiche inchangée',
  push_annul(:n0, :'K') = '' and statut_fiche(:'k') = 'null');
select verifier('N', 'Eliot (qui annule) : aucune push ; une seule push en tout',
  push_annul(:n0, :'E') = '' and d22_nb_push(:n0) = 1);
select verifier('N', 'deuxième annulation : refusée, aucune nouvelle push',
  d22_annuler(:'E', :'p') like '%swend_inactif%' and d22_nb_push(:n0) = 1);
select verifier('N', 'Swend annulé : plus de demande possible',
  en_tant_que(:'E', format('select envoyer_demande_remplacement(%L)', :'k')) like '%swend_inactif%');

-- David (destinataire) peut aussi annuler.
select swend_annulable() as p \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select d22_annuler(:'D', :'p') as r \gset
select verifier('N', 'David (destinataire) annule', :'r' = 'OK' and d22_statut(:'p') = 'annule', :'r');
select verifier('N', 'Eliot : « David a annulé votre Swend… »',
  push_annul(:n0, :'E') = 'Ton Swend est annulé|David a annulé votre Swend du lundi 13 octobre à 20h00 · Au Père Lapin.',
  push_annul(:n0, :'E'));

-- ===================================================================
-- B. Eliot en recherche : demandes en attente clôturées
-- ===================================================================
select swend_annulable() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Thomas', '0600000005') as t \gset
select d22_demander(:'E', :'k');
select d22_demander(:'E', :'c');
select d22_demander(:'E', :'t');
select en_tant_que(:'T', format('select repondre_demande_remplacement(%L, false)', :'t')) as r \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('B', 'Eliot annule malgré ses demandes en cours', d22_annuler(:'E', :'p') = 'OK');
select verifier('B', 'demandes en attente clôturées (Kevin, Camille), refus conservé (Thomas)',
  statut_fiche(:'k') = 'cloturee' and statut_fiche(:'c') = 'cloturee' and statut_fiche(:'t') = 'refusee',
  statut_fiche(:'k') || ' / ' || statut_fiche(:'c') || ' / ' || statut_fiche(:'t'));
select verifier('B', 'Kevin : « La demande n’est plus d’actualité »',
  push_annul(:n0, :'K') = 'La demande n’est plus d’actualité|Le Swend a été annulé.', push_annul(:n0, :'K'));
select verifier('B', 'Camille : même push',
  push_annul(:n0, :'C') = 'La demande n’est plus d’actualité|Le Swend a été annulé.', push_annul(:n0, :'C'));
select verifier('B', 'push de Kevin : ouvre sa conversation avec Eliot',
  (select data->>'type' = 'chat' and data->>'remplacant_id' = :'k' and data->>'nom_interlocuteur' = 'Eliot E'
   from notifications_log where id > :n0 and profile_id = :'K'));
select verifier('B', 'Thomas (déjà refusé) : aucune push', push_annul(:n0, :'T') = '');
select verifier('B', 'jamais « C''est bon, quelqu''un a pu prendre la place »',
  not exists (select 1 from notifications_log where id > :n0 and corps like '%quelqu''un a pu prendre la place%'));
select verifier('B', 'David prévenu ; 3 push en tout',
  push_annul(:n0, :'D') like 'Ton Swend est annulé|Eliot a annulé votre Swend%' and d22_nb_push(:n0) = 3);
select verifier('B', 'événement « clôture » dans les fils de Kevin et Camille',
  (select count(*) from evenements_fil where remplacant_id in (:'k', :'c') and code = 'demande_cloturee') = 2);
select verifier('B', 'Kevin ne peut plus accepter',
  en_tant_que(:'K', format('select repondre_demande_remplacement(%L, true)', :'k')) <> 'OK' and statut_fiche(:'k') = 'cloturee');

-- ===================================================================
-- R. Kevin a accepté de remplacer Eliot : Eliot peut quand même annuler
-- ===================================================================
select swend_annulable() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select d22_demander(:'E', :'k');
select d22_demander(:'E', :'c');
select d22_accepter(:'K', :'k');
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('R', 'Kevin (remplaçant accepté) ne peut pas annuler', d22_annuler(:'K', :'p') like '%non_autorise%');
select d22_annuler(:'E', :'p') as r \gset
select verifier('R', 'Eliot annule même si Kevin a accepté', :'r' = 'OK' and d22_statut(:'p') = 'annule', :'r');
select verifier('R', 'Kevin : « Eliot a annulé le Swend du … »',
  push_annul(:n0, :'K') = 'Le Swend est annulé|Eliot a annulé le Swend du lundi 13 octobre à 20h00 · Au Père Lapin.',
  push_annul(:n0, :'K'));
select verifier('R', 'Camille (demande déjà close quand Kevin a accepté) : aucune push', push_annul(:n0, :'C') = '');
select verifier('R', 'David : aucune mention de Kevin ; 2 push en tout',
  push_annul(:n0, :'D') not like '%Kevin%' and d22_nb_push(:n0) = 2);
select verifier('R', 'Kevin ne peut plus se désister d''un Swend annulé',
  en_tant_que(:'K', format('select se_desister_du_remplacement(%L)', :'k')) like '%swend_inactif%');
select verifier('R', 'conversation Eliot ↔ Kevin toujours accessible (Eliot écrit, Kevin lit)',
  en_tant_que(:'E', format('insert into messages (remplacant_id, expediteur_id, contenu) values (%L, %L, %L)', :'k', :'E', 'Merci quand même'))= 'OK'
  and compter_en_tant_que(:'K', format('select count(*)::int from messages where remplacant_id = %L and contenu = %L', :'k', 'Merci quand même')) = 1);

-- R2. Kevin remplace Eliot, mais c'est David qui annule
select swend_annulable() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select d22_demander(:'E', :'k');
select d22_accepter(:'K', :'k');
select coalesce(max(id), 0) as n0 from notifications_log \gset
select d22_annuler(:'D', :'p') as r \gset
select verifier('R', 'David annule alors que Kevin remplace Eliot', :'r' = 'OK' and d22_statut(:'p') = 'annule', :'r');
select verifier('R', 'Kevin : « David a annulé le Swend du … »',
  push_annul(:n0, :'K') = 'Le Swend est annulé|David a annulé le Swend du lundi 13 octobre à 20h00 · Au Père Lapin.',
  push_annul(:n0, :'K'));
select verifier('R', 'Eliot : « David a annulé votre Swend du … » (inchangé) ; David : rien ; 2 push en tout',
  push_annul(:n0, :'E') = 'Ton Swend est annulé|David a annulé votre Swend du lundi 13 octobre à 20h00 · Au Père Lapin.'
  and push_annul(:n0, :'D') = '' and d22_nb_push(:n0) = 2, push_annul(:n0, :'E'));

-- ===================================================================
-- X. Camille remplace David, Kevin sollicité par Eliot : Eliot annule
-- ===================================================================
select swend_annulable() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Camille', '0600000004') as c \gset
select d22_demander(:'D', :'c');
select d22_accepter(:'C', :'c');
select d22_demander(:'E', :'k');
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('X', 'Eliot annule', d22_annuler(:'E', :'p') = 'OK');
select verifier('X', 'Camille (remplaçante de David) : « Eliot a annulé le Swend du … »',
  push_annul(:n0, :'C') = 'Le Swend est annulé|Eliot a annulé le Swend du lundi 13 octobre à 20h00 · Au Père Lapin.',
  push_annul(:n0, :'C'));
select verifier('X', 'Kevin : « La demande n’est plus d’actualité »',
  push_annul(:n0, :'K') = 'La demande n’est plus d’actualité|Le Swend a été annulé.');
select verifier('X', 'David : aucune mention de Camille ni de Kevin',
  push_annul(:n0, :'D') = 'Ton Swend est annulé|Eliot a annulé votre Swend du lundi 13 octobre à 20h00 · Au Père Lapin.');
select verifier('X', 'Eliot : aucune push ; 3 en tout', push_annul(:n0, :'E') = '' and d22_nb_push(:n0) = 3);

-- ===================================================================
-- M. Kevin sollicité des deux côtés : une seule push
-- ===================================================================
select swend_annulable() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche(:'D', :'p', 'destinataire', 'Kevin', '0600000003') as k2 \gset
select d22_demander(:'E', :'k');
select d22_demander(:'D', :'k2');
select coalesce(max(id), 0) as n0 from notifications_log \gset
select verifier('M', 'David annule', d22_annuler(:'D', :'p') = 'OK');
select verifier('M', 'les deux demandes à Kevin sont closes', statut_fiche(:'k') = 'cloturee' and statut_fiche(:'k2') = 'cloturee');
select verifier('M', 'Kevin : une seule push', push_annul(:n0, :'K') = 'La demande n’est plus d’actualité|Le Swend a été annulé.', push_annul(:n0, :'K'));

-- ===================================================================
-- H. Jusqu'à l'heure du rendez-vous seulement
-- ===================================================================
select swend_annulable(date_trunc('minute', now()) - interval '1 minute') as p \gset
select verifier('H', 'après l''heure du rendez-vous : annulation refusée',
  d22_annuler(:'E', :'p') like '%swend_passe%' and d22_statut(:'p') = 'confirme', d22_annuler(:'E', :'p'));
select swend_annulable(now() + interval '10 minutes') as p \gset
select verifier('H', 'dix minutes avant : annulation possible', d22_annuler(:'E', :'p') = 'OK');

-- ===================================================================
-- G. Le statut d'un Swend scellé ne se change plus directement
-- ===================================================================
select swend_annulable() as p \gset
select verifier('G', 'Eliot ne peut pas annuler par une écriture directe',
  en_tant_que(:'E', format('update pactes set statut = %L where id = %L', 'annule', :'p')) like '%statut_protege%'
  and d22_statut(:'p') = 'confirme');
select verifier('G', 'ni passer le Swend à un autre statut',
  en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'maintenu', :'p')) like '%statut_protege%');
select d22_annuler(:'E', :'p') as r \gset
select verifier('G', 'un Swend annulé ne peut pas être ranimé par l''app',
  en_tant_que(:'E', format('update pactes set statut = %L where id = %L', 'confirme', :'p')) like '%statut_protege%'
  and d22_statut(:'p') = 'annule');
select swend_en_negociation() as pn \gset
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'annule', :'pn')) as r \gset
select verifier('G', 'négociation inchangée : David refuse par écriture directe', :'r' = 'OK' and d22_statut(:'pn') = 'annule', :'r');
select verifier('G', 'annuler_swend ne s''applique pas à un Swend non scellé',
  (select d22_annuler(:'E', swend_en_negociation()) like '%swend_inactif%'));

-- ===================================================================
-- S. Suppression : jamais un Swend scellé
-- ===================================================================
select swend_annulable() as p \gset
select verifier('S', 'Swend scellé : suppression refusée',
  en_tant_que(:'E', format('select supprimer_pacte(%L)', :'p')) like '%swend_scelle%' and d22_statut(:'p') = 'confirme');
select d22_annuler(:'E', :'p') as r \gset
select verifier('S', 'Swend scellé puis annulé : suppression refusée (reste dans l''historique)',
  en_tant_que(:'E', format('select supprimer_pacte(%L)', :'p')) like '%swend_scelle%' and d22_statut(:'p') = 'annule');
select verifier('S', 'suppression directe par l''app sans effet',
  en_tant_que(:'E', format('delete from pactes where id = %L', :'p')) is not null and d22_statut(:'p') = 'annule');
select swend_en_negociation() as pn \gset
select en_tant_que(:'E', format('select supprimer_pacte(%L)', :'pn')) as r \gset
select verifier('S', 'Swend jamais scellé : suppression possible',
  :'r' = 'OK' and not exists (select 1 from pactes where id = :'pn'), :'r');
select verifier('S', 'mes_swends_scelles : les Swends scellés d''Eliot, y compris annulés',
  compter_en_tant_que(:'E', format('select count(*)::int from mes_swends_scelles() s where s = %L', :'p')) = 1
  and compter_en_tant_que(:'E', 'select count(*)::int from mes_swends_scelles()')
      = (select count(*) from pactes where scelle_le is not null and :'E' in (initiateur_id, destinataire_id)));
select verifier('S', 'mes_swends_scelles : rien pour une personne de confiance', compter_en_tant_que(:'K', 'select count(*)::int from mes_swends_scelles()') = 0);
with d as (delete from pactes where id = :'p' returning 1)
select verifier('S', 'suppression interne (hors app) toujours possible', (select count(*) from d) = 1);

-- ===================================================================
-- V. Réservation (D-020) : rien d'automatique, la vue interne suit
-- ===================================================================
select swend_annulable() as p \gset
update reservations_suivi set statut_reservation = 'reservee' where pacte_id = :'p';
select d22_annuler(:'E', :'p') as r \gset
select verifier('V', 'table réservée : statut inchangé, « Annuler la réservation au restaurant »',
  (select statut_reservation = 'reservee' and a_faire = 'Annuler la réservation au restaurant' and statut_swend = 'annule'
   from reservations_a_suivre where swend_id = :'p'));
select swend_annulable() as p \gset
select d22_annuler(:'E', :'p') as r \gset
select verifier('V', 'table pas encore réservée : aucune action (ni réserver, ni annuler)',
  (select statut_reservation = 'a_reserver' and a_faire = '' from reservations_a_suivre where swend_id = :'p'));

-- ===================================================================
-- P. Plus aucun rappel après l'annulation
-- ===================================================================
select swend_annulable() as p \gset
select d22_annuler(:'E', :'p') as r \gset
select coalesce(max(id), 0) as n0 from notifications_log \gset
select envoyer_rappels_dus('2031-10-06 16:00+00');
select verifier('P', 'J-7 : aucun rappel pour un Swend annulé',
  not exists (select 1 from notifications_log where id > :n0 and data->>'pacte_id' = :'p'));

-- ===================================================================
-- Q. Qui a annulé, et quand (annule_par / annule_le)
-- ===================================================================
create or replace function d22_auteur(p uuid) returns text language sql as $$
  select coalesce(annule_par::text, 'null') || '|' || case when annule_le is null then 'null' else 'date' end
  from pactes where id = p
$$;
select swend_annulable() as p \gset
select ajouter_fiche(:'E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select d22_demander(:'E', :'k');
select d22_accepter(:'K', :'k');
select verifier('Q', 'Swend actif : ni auteur ni date', d22_auteur(:'p') = 'null|null');
select verifier('Q', 'Kevin (remplaçant accepté) ne peut toujours pas annuler ; rien n''est enregistré',
  d22_annuler(:'K', :'p') like '%non_autorise%' and d22_auteur(:'p') = 'null|null');
select now() as t0 \gset
select d22_annuler(:'E', :'p') as r \gset
select verifier('Q', 'Eliot annule → annule_par = Eliot', :'r' = 'OK' and (select annule_par from pactes where id = :'p') = :'E', :'r');
select verifier('Q', 'annule_le renseigné au moment de l''annulation',
  (select annule_le >= :'t0'::timestamptz and annule_le <= now() from pactes where id = :'p'));
select verifier('Q', 'statut, auteur et date écrits ensemble',
  (select statut = 'annule' and annule_par is not null and annule_le is not null from pactes where id = :'p'));

select swend_annulable() as p2 \gset
select d22_annuler(:'D', :'p2') as r \gset
select verifier('Q', 'David annule → annule_par = David', :'r' = 'OK' and (select annule_par from pactes where id = :'p2') = :'D', :'r');
select verifier('Q', 'annule_le renseigné (David)', (select annule_le is not null from pactes where id = :'p2'));

-- L'app ne peut pas falsifier ces champs.
select swend_annulable() as p3 \gset
select verifier('Q', 'Swend actif : Eliot ne peut pas écrire annule_par / annule_le',
  en_tant_que(:'E', format('update pactes set annule_par = %L, annule_le = now() where id = %L', :'E', :'p3')) like '%modification_interdite%'
  and d22_auteur(:'p3') = 'null|null');
select verifier('Q', 'Swend annulé par Eliot : David ne peut pas se l''attribuer',
  en_tant_que(:'D', format('update pactes set annule_par = %L where id = %L', :'D', :'p')) like '%modification_interdite%'
  and (select annule_par from pactes where id = :'p') = :'E');
select verifier('Q', '... ni changer la date',
  en_tant_que(:'E', format('update pactes set annule_le = %L where id = %L', '2020-01-01 12:00+00', :'p')) like '%modification_interdite%');
select verifier('Q', '... ni effacer l''auteur',
  en_tant_que(:'E', format('update pactes set annule_par = null, annule_le = null where id = %L', :'p')) like '%modification_interdite%'
  and (select annule_par from pactes where id = :'p') = :'E');
select verifier('Q', 'création d''un Swend avec un auteur d''annulation : refusée',
  en_tant_que(:'E', format(
    'insert into pactes (statut, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone, annule_par, annule_le) values (%L, %L, %L, %L, %L, %L, now())',
    'enAttenteChoixDateDestinataire', :'E', 'Eliot E', 'Faux3', '06 00 00 00 02', :'E')) like '%modification_interdite%');

-- Seule annuler_swend() renseigne ces champs.
select swend_en_negociation() as pn \gset
select en_tant_que(:'D', format('update pactes set statut = %L where id = %L', 'annule', :'pn')) as r \gset
select verifier('Q', 'refus pendant la négociation : annulé, auteur non renseigné',
  :'r' = 'OK' and d22_statut(:'pn') = 'annule' and d22_auteur(:'pn') = 'null|null', :'r');
select swend_annulable() as pd \gset
select ajouter_fiche(:'E', :'pd', 'initiateur', 'Kevin', '0600000003') as kd \gset
select ajouter_fiche(:'D', :'pd', 'destinataire', 'Camille', '0600000004') as cd \gset
select d22_demander(:'E', :'kd');
select d22_accepter(:'K', :'kd');
select d22_demander(:'D', :'cd');
select d22_accepter(:'C', :'cd');
select verifier('Q', 'double remplacement : annulé automatiquement, auteur non renseigné',
  d22_statut(:'pd') = 'annuleDoubleAbsence' and d22_auteur(:'pd') = 'null|null');

-- Anciennes annulations (avant D-022) : auteur et date inconnus, restent NULL.
insert into pactes (statut, type, date_retenue, restaurant_id, initiateur_id, initiateur_nom,
                    destinataire_id, destinataire_nom, destinataire_telephone)
values ('confirme', 'diner', '2031-11-03 19:00+00', '00000000-0000-0000-0000-0000000000aa',
        :'E', 'Eliot E', :'D', 'David D', '06 00 00 00 02')
returning id as ph \gset
update pactes set statut = 'annule' where id = :'ph';
select verifier('Q', 'ancienne annulation : annule_par / annule_le NULL, Swend valide',
  d22_statut(:'ph') = 'annule' and d22_auteur(:'ph') = 'null|null'
  and (select scelle_le is not null from pactes where id = :'ph'));
select verifier('Q', 'ancienne annulation : toujours lisible par ses titulaires',
  compter_en_tant_que(:'E', format('select count(*)::int from pactes where id = %L', :'ph')) = 1
  and compter_en_tant_que(:'D', format('select count(*)::int from pactes where id = %L', :'ph')) = 1);
select verifier('Q', 'ancienne annulation : dans l''historique (Swend scellé), non supprimable, non ré-annulable',
  compter_en_tant_que(:'E', format('select count(*)::int from mes_swends_scelles() s where s = %L', :'ph')) = 1
  and en_tant_que(:'E', format('select supprimer_pacte(%L)', :'ph')) like '%swend_scelle%'
  and d22_annuler(:'E', :'ph') like '%swend_inactif%');
select verifier('Q', 'ancienne annulation : suivi de réservation inchangé',
  (select statut_swend = 'annule' and a_faire = '' from reservations_a_suivre where swend_id = :'ph'));

-- Intervention interne (SQL Editor / service role) toujours possible.
update pactes set annule_par = :'E', annule_le = '2031-10-01 10:00+00' where id = :'ph';
select verifier('Q', 'interne : l''équipe peut renseigner l''auteur si elle le connaît',
  (select annule_par from pactes where id = :'ph') = :'E');
update pactes set annule_par = null, annule_le = null where id = :'ph';
select verifier('Q', 'interne : et revenir à « inconnu »', d22_auteur(:'ph') = 'null|null');
do $$ begin
  begin
    update pactes set annule_par = '00000000-0000-0000-0000-00000000000e'
    where id = (select id from pactes where statut = 'annule' and annule_par is null limit 1);
    perform verifier('Q', 'auteur sans date : refusé (contrainte)', false);
  exception when check_violation then
    perform verifier('Q', 'auteur sans date : refusé (contrainte)', true);
  end;
end $$;

select scenario, verif, case when ok then 'OK' else 'ÉCHEC' end as resultat, detail from test_resultats order by id;
select count(*) filter (where ok) as reussis, count(*) filter (where ok is not true) as echecs from test_resultats;
