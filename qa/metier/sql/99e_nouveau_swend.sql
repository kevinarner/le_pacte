-- « Faire un nouveau Swend » et fermeture du chat après le Swend (D-023c).
-- Utilise les outils de 10_imprevu.sql (verifier, en_tant_que) et
-- 99b_chat_apres_swend.sql (cs_lire, cs_envoyer). Personnes propres à cette
-- suite (aucun lien avec les autres) ; Swends des chats datés dans le passé
-- réel (le moteur et le gel sont appelés avec now()), nouveaux Swends à
-- venir.
\set ON_ERROR_STOP 1
\pset footer off
delete from test_resultats;

\set A '00000000-0000-0000-0000-000000000301'
\set B '00000000-0000-0000-0000-000000000302'
\set C '00000000-0000-0000-0000-000000000303'
\set D '00000000-0000-0000-0000-000000000304'
\set F '00000000-0000-0000-0000-000000000305'
\set G '00000000-0000-0000-0000-000000000306'
\set H '00000000-0000-0000-0000-000000000307'
\set J '00000000-0000-0000-0000-000000000308'
\set L '00000000-0000-0000-0000-000000000309'
\set M '00000000-0000-0000-0000-00000000030a'
\set N '00000000-0000-0000-0000-00000000030b'
\set P '00000000-0000-0000-0000-00000000030c'
\set Q '00000000-0000-0000-0000-00000000030d'
\set W '00000000-0000-0000-0000-00000000030e'

insert into profiles (id, prenom, nom, telephone) values
 ('00000000-0000-0000-0000-000000000301', 'Alma', 'A', '0613000001'),
 ('00000000-0000-0000-0000-000000000302', 'Basile', 'B', '0613000002'),
 ('00000000-0000-0000-0000-000000000303', 'Kevin', 'K', '0613000003'),
 ('00000000-0000-0000-0000-000000000304', 'Diane', 'D', '0613000004'),
 ('00000000-0000-0000-0000-000000000305', 'Fanny', 'F', '0613000005'),
 ('00000000-0000-0000-0000-000000000306', 'Gaspard', 'G', '0613000006'),
 ('00000000-0000-0000-0000-000000000307', 'Hector', 'H', '0613000007'),
 ('00000000-0000-0000-0000-000000000308', 'Jade', 'J', '0613000008'),
 ('00000000-0000-0000-0000-000000000309', 'Louis', 'L', '0613000009'),
 ('00000000-0000-0000-0000-00000000030a', 'Mila', 'M', '0613000010'),
 ('00000000-0000-0000-0000-00000000030b', 'Nina', 'N', '0613000011'),
 ('00000000-0000-0000-0000-00000000030c', 'Paul', 'P', '0613000012'),
 ('00000000-0000-0000-0000-00000000030d', 'Quentin', 'Q', '0613000013'),
 ('00000000-0000-0000-0000-00000000030e', 'Wanda', 'W', '0613000014')
on conflict do nothing;
-- Les chats de cette suite s'ouvrent dans le passé réel.
update chat_apres_swend_service set mise_en_service = now() - interval '60 days';

-- ---------- outils ----------
-- Swend p_a (initiateur) → p_b (destinataire, retrouvé par son numéro).
-- Scellé à l'insertion si p_statut = 'confirme' (date retenue = p_date).
create or replace function nv_swend(p_a uuid, p_b uuid, p_date timestamptz, p_statut text default 'confirme')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into pactes (statut, type, date_retenue, dates_proposees, restaurant_id, initiateur_id,
                      initiateur_nom, destinataire_nom, destinataire_telephone)
  values (p_statut, 'diner', case when p_statut = 'confirme' then p_date end, to_jsonb(array[p_date]),
          '00000000-0000-0000-0000-0000000000aa', p_a,
          (select prenom || ' ' || nom from profiles where id = p_a),
          (select prenom || ' ' || nom from profiles where id = p_b),
          (select telephone from profiles where id = p_b))
  returning id into v;
  return v;
end $$;
-- Scelle une invitation sur sa première date proposée (chemin de l'app :
-- UPDATE du statut ; scelle_le posé par la base).
create or replace function nv_sceller(p uuid) returns void language sql as $$
  update pactes set statut = 'confirme', date_retenue = (instants_proposes(dates_proposees))[1] where id = p
$$;
-- Remplaçant sélectionné (compte p_profil) du côté p_cote.
create or replace function nv_remplacant(p uuid, p_cote text, p_profil uuid) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into remplacants (pacte_id, cote, prenom, nom, telephone, email)
  select p, p_cote, prenom, nom, telephone, '' from profiles where id = p_profil
  returning id into v;
  update remplacants set demande_statut = 'acceptee', selectionne = true where id = v;
  return v;
end $$;
-- Gel et moteur à l'instant donné ; renvoie le chat du Swend (ou null).
create or replace function nv_ouvrir(p uuid, p_maintenant timestamptz default now()) returns uuid
language plpgsql as $$
begin
  perform figer_swends_passes(least(p_maintenant, now()));
  perform ouvrir_chats_apres_swend(p_maintenant);
  return (select id from chats_apres_swend where pacte_id = p);
end $$;
create or replace function nv_etat(p_chat uuid) returns text language sql as $$
  select case when ferme_le is null then 'ouvert' else 'ferme:' || motif_fermeture end
         || '|systeme=' || (select count(*) from messages_apres_swend m where m.chat_id = c.id and m.genre = 'systeme')
  from chats_apres_swend c where c.id = p_chat
$$;
create or replace function nv_n0() returns bigint language sql as $$
  select coalesce(max(id), 0) from notifications_log
$$;
create or replace function nv_creer(p_user uuid, p_chat uuid, p_participant uuid, p_date timestamptz,
                                    p_remplacants jsonb default '[]') returns text
language plpgsql as $$
declare v text;
begin
  v := cs_lire(p_user, format(
    'select creer_swend_depuis_chat(%L, %L, %L, %L::jsonb, %L, %L::jsonb)::text',
    p_chat, p_participant, 'diner', to_jsonb(array[p_date])::text,
    '00000000-0000-0000-0000-0000000000aa', p_remplacants::text));
  return v;
end $$;
create or replace function nv_options(p_user uuid, p_chat uuid) returns text language sql as $$
  select cs_lire(p_user, format(
    $q$select coalesce(string_agg(prenom || ':' || case when deja_en_cours then 'en_cours' else 'libre' end, ',' order by prenom), '')
       from options_nouveau_swend(%L)$q$, p_chat))
$$;
create or replace function nv_participant(p_chat uuid, p_profil uuid) returns uuid language sql as $$
  select id from participants_chat_apres_swend where chat_id = p_chat and profil_id = p_profil
$$;

-- ===================================================================
-- A. Chat à 2 : scellement d'un nouveau Swend entre les deux → fermeture
-- ===================================================================
select nv_swend(:'A', :'B', now() - interval '10 days') as s1 \gset
select nv_ouvrir(:'s1') as c1 \gset
select verifier('A', 'chat à 2 ouvert (Alma, Basile)', nv_etat(:'c1') = 'ouvert|systeme=0', nv_etat(:'c1'));
select cs_envoyer(:'A', :'c1', 'Super soirée !') as r \gset
select nv_swend(:'B', :'A', now() + interval '30 days', 'enAttenteChoixDateDestinataire') as n1 \gset
select verifier('A', 'invitation (Basile → Alma) : rien ne ferme', nv_etat(:'c1') = 'ouvert|systeme=0', nv_etat(:'c1'));
update pactes set statut = 'enAttenteChoixDateInitiateur', nombre_echanges_date = nombre_echanges_date + 1,
  dates_proposees = to_jsonb(array[now() + interval '31 days']) where id = :'n1';
select verifier('A', 'négociation (contre-proposition) : rien ne ferme', nv_etat(:'c1') = 'ouvert|systeme=0', nv_etat(:'c1'));
select nv_n0() as n0 \gset
select nv_sceller(:'n1');
select verifier('A', 'scellement entre les deux : chat fermé (nouveau_swend), un message système',
  nv_etat(:'c1') = 'ferme:nouveau_swend|systeme=1', nv_etat(:'c1'));
select verifier('A', 'texte exact du message système, sans auteur ni heure',
  (select contenu = E'Un nouveau Swend a été scellé.\nCe chat est désormais fermé pour préserver le silence.'
          and participant_id is null
   from messages_apres_swend where chat_id = :'c1' and genre = 'systeme'));
select verifier('A', 'message système daté de la fermeture, après les messages existants (ordre chronologique)',
  (select m.created_at = c.ferme_le from messages_apres_swend m join chats_apres_swend c on c.id = m.chat_id
   where m.chat_id = :'c1' and m.genre = 'systeme')
  and (select max(created_at) from messages_apres_swend where chat_id = :'c1' and genre = 'texte')
      < (select created_at from messages_apres_swend where chat_id = :'c1' and genre = 'systeme'));
select verifier('A', 'aucune push de fermeture (seule celle du scellement du nouveau Swend)',
  not exists (select 1 from notifications_log where id > :n0 and profile_id in (:'A', :'B')
              and (data->>'pacte_id' is distinct from :'n1' or data->>'chat_id' is not null
                   or data->>'type' = 'chat_apres_swend')),
  (select string_agg(titre || ' / ' || coalesce(data::text, ''), ' ## ') from notifications_log where id > :n0));
select verifier('A', 'historique lisible, écriture refusée (chat_ferme)',
  cs_lire(:'B', format('select count(*)::text from messages_apres_swend where chat_id = %L', :'c1')) = '2'
  and cs_envoyer(:'B', :'c1', 'encore un mot') like '%chat_ferme%');
select verifier('A', 'mes_chats_apres_swend : fermé, motif nouveau_swend ; le message système n''est pas un non-lu',
  cs_lire(:'B', format('select motif_fermeture || ''|'' || non_lus from mes_chats_apres_swend() where chat_id = %L', :'c1'))
    = 'nouveau_swend|1');

-- Annulation du nouveau Swend juste après : rien ne rouvre, aucun message.
update pactes set statut = 'annule' where id = :'n1';
select verifier('A', 'annulation après scellement : chat toujours fermé, toujours un seul message, aucun ajout',
  nv_etat(:'c1') = 'ferme:nouveau_swend|systeme=1'
  and (select count(*) from messages_apres_swend where chat_id = :'c1') = 2, nv_etat(:'c1'));
select verifier('A', 'aucun Swend actif entre eux après l''annulation', not swend_actif_entre(:'A', :'B'));

-- ===================================================================
-- B. Annulation sans scellement ; un seul participant en commun
-- ===================================================================
select nv_swend(:'C', :'D', now() - interval '12 days') as s2 \gset
select nv_ouvrir(:'s2') as c2 \gset
select nv_swend(:'C', :'D', now() + interval '30 days', 'enAttenteChoixDateDestinataire') as n2 \gset
update pactes set statut = 'annule' where id = :'n2';
select verifier('B', 'invitation annulée sans scellement : chat ouvert', nv_etat(:'c2') = 'ouvert|systeme=0', nv_etat(:'c2'));
select nv_swend(:'C', :'F', now() + interval '30 days') as n3 \gset
select nv_swend(:'W', :'D', now() + interval '31 days') as n3b \gset
select verifier('B', 'Swends scellés avec une seule des deux personnes : chat ouvert',
  nv_etat(:'c2') = 'ouvert|systeme=0', nv_etat(:'c2'));
-- Scellé dès l'insertion (point d'entrée quelconque) : même fermeture.
select nv_swend(:'D', :'C', now() + interval '40 days') as n4 \gset
select verifier('B', 'Swend inséré déjà scellé (Diane → Kevin) : chat fermé',
  nv_etat(:'c2') = 'ferme:nouveau_swend|systeme=1', nv_etat(:'c2'));

-- ===================================================================
-- C. Chat à 3 : chacune des 3 paires ferme (remplaçant compris)
-- ===================================================================
-- Trois chats successifs Fanny (initiatrice) / Gaspard (destinataire) /
-- Hector (remplaçant de Gaspard), un par paire testée.
select nv_swend(:'F', :'G', now() - interval '20 days') as t1 \gset
select nv_remplacant(:'t1', 'destinataire', :'H') as r1 \gset
select nv_ouvrir(:'t1') as ct1 \gset
select verifier('C', 'chat à 3 ouvert : Fanny, Gaspard, Hector (place de Gaspard)',
  (select string_agg(role || ':' || prenom_affiche, ',' order by role) from participants_chat_apres_swend where chat_id = :'ct1')
  = 'destinataire:Gaspard,initiateur:Fanny,remplacant:Hector');
select nv_swend(:'F', :'G', now() + interval '30 days') as p1 \gset
select verifier('C', 'paire titulaire ↔ titulaire (Fanny, Gaspard) : fermé', nv_etat(:'ct1') = 'ferme:nouveau_swend|systeme=1', nv_etat(:'ct1'));
update pactes set statut = 'annule' where id = :'p1';

select nv_swend(:'F', :'G', now() - interval '18 days') as t2 \gset
select nv_remplacant(:'t2', 'destinataire', :'H') as r2 \gset
select nv_ouvrir(:'t2') as ct2 \gset
select nv_swend(:'H', :'F', now() + interval '30 days', 'enAttenteChoixDateDestinataire') as p2 \gset
select verifier('C', 'invitation titulaire ↔ remplaçant : rien ne ferme', nv_etat(:'ct2') = 'ouvert|systeme=0', nv_etat(:'ct2'));
select nv_sceller(:'p2');
select verifier('C', 'paire titulaire ↔ remplaçant (Hector, Fanny) : fermé', nv_etat(:'ct2') = 'ferme:nouveau_swend|systeme=1', nv_etat(:'ct2'));
update pactes set statut = 'annule' where id = :'p2';

select nv_swend(:'F', :'G', now() - interval '16 days') as t3 \gset
select nv_remplacant(:'t3', 'destinataire', :'H') as r3 \gset
select nv_ouvrir(:'t3') as ct3 \gset
select nv_swend(:'G', :'H', now() + interval '30 days') as p3 \gset
select verifier('C', 'paire remplacé ↔ remplaçant (Gaspard, Hector) : fermé', nv_etat(:'ct3') = 'ferme:nouveau_swend|systeme=1', nv_etat(:'ct3'));

-- Deux scellements successifs (une autre paire du même ancien chat) : un
-- seul message, fermeture inchangée.
select ferme_le as f_avant from chats_apres_swend where id = :'ct3' \gset
select nv_swend(:'F', :'H', now() + interval '35 days') as p4 \gset
select verifier('C', 'deuxième scellement (Fanny, Hector) : toujours un seul message système, date inchangée',
  nv_etat(:'ct3') = 'ferme:nouveau_swend|systeme=1'
  and (select ferme_le from chats_apres_swend where id = :'ct3') = :'f_avant'::timestamptz, nv_etat(:'ct3'));
select verifier('C', 'participants potentiels (logique du moteur) : Fanny, Gaspard, Hector à la place de Gaspard',
  (select string_agg(rang || ':' || role || ':' || coalesce(place_de, '-'), ',' order by rang)
   from participants_potentiels_chat_apres_swend(:'t3')) = '1:initiateur:-,2:destinataire:-,3:remplacant:destinataire');

-- ===================================================================
-- D. Chat pas encore ouvert : ne s'ouvrira jamais
-- ===================================================================
-- Swend passé il y a une heure : figé, chat prévu plus tard.
select nv_swend(:'J', :'L', now() - interval '1 hour') as u1 \gset
select coalesce(nv_ouvrir(:'u1')::text, '') as cu1 \gset
select verifier('D', 'avant l''heure d''ouverture : pas de chat', :'cu1' = '');
select nv_swend(:'L', :'J', now() + interval '30 days', 'enAttenteChoixDateDestinataire') as v1 \gset
select verifier('D', 'invitation entre eux : rien n''est décidé',
  not exists (select 1 from chats_apres_swend_jamais_ouverts where pacte_id = :'u1'));
select nv_n0() as n0 \gset
select nv_sceller(:'v1');
select verifier('D', 'scellement entre eux avant l''ouverture : chat marqué « jamais ouvert »',
  (select motif = 'nouveau_swend' and nouveau_pacte_id = :'v1' from chats_apres_swend_jamais_ouverts where pacte_id = :'u1'));
select coalesce(nv_ouvrir(:'u1', now() + interval '2 days')::text, '') as cu1 \gset
select verifier('D', 'heure d''ouverture passée : aucun chat, aucun message système, aucune anomalie',
  :'cu1' = '' and not exists (select 1 from anomalies_chat_apres_swend where pacte_id = :'u1'));
update pactes set statut = 'annule' where id = :'v1';
select coalesce(nv_ouvrir(:'u1', now() + interval '3 days')::text, '') as cu1 \gset
select verifier('D', 'annulation du nouveau Swend : le chat ne s''ouvre toujours pas',
  :'cu1' = '');
select verifier('D', 'aucune push (ni fermeture, ni « Alors, ce Swend ? »)',
  not exists (select 1 from notifications_log where id > :n0 and profile_id in (:'J', :'L')
              and (data->>'pacte_id' = :'u1' or data->>'type' = 'chat_apres_swend'
                   or (data->>'pacte_id' is distinct from :'v1'))),
  (select string_agg(titre, ' ## ') from notifications_log where id > :n0));
select verifier('D', 'le Swend passé reste consultable par ses participants',
  cs_lire(:'J', format('select count(id)::text from pactes where id = %L', :'u1')) = '1');

-- À 3 : Mila (initiatrice) remplacée par Nina, Paul (destinataire) ; un
-- nouveau Swend entre la remplaçante et l'autre titulaire bloque aussi. Un
-- Swend avec une seule des personnes ne bloque rien.
select nv_swend(:'M', :'P', now() - interval '2 hours') as u2 \gset
select nv_remplacant(:'u2', 'initiateur', :'N') as ru2 \gset
select nv_swend(:'Q', :'W', now() - interval '3 hours') as u3 \gset
select coalesce(nv_ouvrir(:'u2')::text, '') as cu2 \gset
select nv_swend(:'N', :'P', now() + interval '30 days') as v2 \gset
select nv_swend(:'Q', :'M', now() + interval '30 days') as v3 \gset
select verifier('D', 'à 3 : remplaçant ↔ titulaire scellé avant l''ouverture → jamais ouvert ; une seule personne en commun → rien',
  exists (select 1 from chats_apres_swend_jamais_ouverts where pacte_id = :'u2')
  and not exists (select 1 from chats_apres_swend_jamais_ouverts where pacte_id = :'u3'));
select coalesce(nv_ouvrir(:'u3', now() + interval '2 days')::text, '') as cu3 \gset
select verifier('D', 'le chat non concerné s''ouvre normalement ; le chat bloqué jamais',
  :'cu3' <> '' and not exists (select 1 from chats_apres_swend where pacte_id = :'u2'));
-- Seul un Swend « précédent » (date antérieure à celle du nouveau) est
-- bloqué : un Swend scellé plus tardif que le nouveau garde son chat.
select nv_swend(:'J', :'L', now() + interval '60 days') as y1 \gset
select nv_swend(:'L', :'J', now() + interval '50 days') as z1 \gset
select verifier('D', 'Swend scellé postérieur au nouveau : pas bloqué',
  not exists (select 1 from chats_apres_swend_jamais_ouverts where pacte_id = :'y1'));

-- ===================================================================
-- E. Un Swend actif par paire ; création depuis le chat (D-024)
-- ===================================================================
-- Chat à 3 neuf : Alma (initiatrice), Diane (destinataire), Kevin
-- (remplaçant de Diane). Aucun Swend en cours entre eux.
select nv_swend(:'A', :'D', now() - interval '25 days') as s5 \gset
select nv_remplacant(:'s5', 'destinataire', :'C') as r5 \gset
select nv_ouvrir(:'s5') as c5 \gset
select verifier('E', 'options d''Alma : Diane et Kevin, libres (pas de rôle, pas de numéro)',
  nv_options(:'A', :'c5') = 'Diane:libre,Kevin:libre', nv_options(:'A', :'c5'));
select verifier('E', 'options : réservé aux participants (non_autorise)',
  nv_options(:'B', :'c5') like 'ERR:%non_autorise%', nv_options(:'B', :'c5'));
select verifier('E', 'options : colonnes renvoyées (participant, prénom, en cours) — jamais un numéro ni un profil',
  pg_get_function_result('public.options_nouveau_swend(uuid)'::regprocedure)
  = 'TABLE(participant_id uuid, prenom text, deja_en_cours boolean)');

-- Swend actif Alma ↔ Kevin (invitation à venir, créée depuis l'accueil).
select nv_swend(:'C', :'A', now() + interval '30 days', 'enAttenteChoixDateDestinataire') as e1 \gset
select verifier('E', 'Swend en cours avec Kevin seulement : seule sa carte est désactivée',
  nv_options(:'A', :'c5') = 'Diane:libre,Kevin:en_cours', nv_options(:'A', :'c5'));
-- Diane et Kevin ont un Swend scellé à venir (section B) : paire par paire.
select verifier('E', 'vu par Diane : Alma libre, Kevin en cours (paire par paire)',
  nv_options(:'D', :'c5') = 'Alma:libre,Kevin:en_cours', nv_options(:'D', :'c5'));
select verifier('E', 'création avec Kevin refusée côté serveur (swend_deja_en_cours)',
  nv_creer(:'A', :'c5', nv_participant(:'c5', :'C'), now() + interval '20 days') like 'ERR:%swend_deja_en_cours%',
  nv_creer(:'A', :'c5', nv_participant(:'c5', :'C'), now() + interval '20 days'));

-- Création avec Diane : D-025 appliqué (compte non fondateur).
select verifier('E', 'date trop proche refusée (D-025, date_trop_proche)',
  nv_creer(:'A', :'c5', nv_participant(:'c5', :'D'), now() + interval '3 days') like 'ERR:%date_trop_proche%');
select verifier('E', 'participant d''un autre chat : refusé (non_autorise)',
  nv_creer(:'A', :'c5', nv_participant(:'c1', :'B'), now() + interval '20 days') like 'ERR:%non_autorise%'
  and nv_creer(:'A', :'c5', nv_participant(:'c5', :'A'), now() + interval '20 days') like 'ERR:%non_autorise%');
select verifier('E', 'tout ou rien : personne de confiance refusée (Diane elle-même) → aucun Swend créé',
  nv_creer(:'A', :'c5', nv_participant(:'c5', :'D'), now() + interval '20 days',
           '[{"prenom":"Diane","nom":"D","telephone":"0613000004","email":""}]') like 'ERR:%'
  and not swend_actif_entre(:'A', :'D'));
select nv_creer(:'A', :'c5', nv_participant(:'c5', :'D'), now() + interval '20 days',
  '[{"prenom":"Wanda","nom":"W","telephone":"06 13 00 00 14","email":""},{"prenom":"Paul","nom":"P","telephone":"0613000012","email":""}]') as e2 \gset
select verifier('E', 'création avec Diane : Swend en attente, Diane retrouvée par la base, D-025 posée',
  (select statut = 'enAttenteChoixDateDestinataire' and initiateur_id = :'A' and destinataire_id = :'D'
          and initiateur_nom = 'Alma A' and destinataire_nom = 'Diane D'
          and date_minimale = (now() at time zone 'Europe/Paris')::date + 15
          and jsonb_array_length(dates_proposees) = 1
   from pactes where id = :'e2'::uuid), :'e2');
select verifier('E', 'personnes de confiance d''Alma enregistrées dans la même transaction',
  (select count(*) from remplacants where pacte_id = :'e2'::uuid and cote = 'initiateur') = 2);
select verifier('E', 'Diane voit l''invitation (push « nouveau Swend » habituelle, sans numéro)',
  cs_lire(:'D', format('select count(id)::text from pactes where id = %L', :'e2')) = '1');
select verifier('E', 'création : le chat reste ouvert (une invitation ne ferme rien)',
  nv_etat(:'c5') = 'ouvert|systeme=0', nv_etat(:'c5'));
select verifier('E', 'seconde création avec Diane refusée (swend_deja_en_cours) ; options à jour',
  nv_creer(:'A', :'c5', nv_participant(:'c5', :'D'), now() + interval '21 days') like 'ERR:%swend_deja_en_cours%'
  and nv_options(:'A', :'c5') = 'Diane:en_cours,Kevin:en_cours', nv_options(:'A', :'c5'));
select verifier('E', 'Diane peut répondre ; Diane ne peut pas recréer (même paire)',
  nv_creer(:'D', :'c5', nv_participant(:'c5', :'A'), now() + interval '22 days') like 'ERR:%swend_deja_en_cours%');
-- Diane accepte la date : scellement → le chat à 3 se ferme.
select nv_sceller(:'e2'::uuid);
select verifier('E', 'scellement du Swend créé depuis le chat : chat fermé, un message système',
  nv_etat(:'c5') = 'ferme:nouveau_swend|systeme=1', nv_etat(:'c5'));
select verifier('E', 'chat fermé : options et création refusées (chat_ferme)',
  nv_options(:'D', :'c5') like 'ERR:%chat_ferme%'
  and nv_creer(:'D', :'c5', nv_participant(:'c5', :'C'), now() + interval '20 days') like 'ERR:%chat_ferme%');

-- ===================================================================
-- F. Swend actif : définition
-- ===================================================================
select nv_swend(:'J', :'M', now() - interval '1 day', 'enAttenteChoixDateDestinataire') as f1 \gset
select verifier('F', 'invitation dont toutes les dates sont passées : pas active', not swend_actif_entre(:'J', :'M'));
select nv_swend(:'J', :'M', now() - interval '1 day') as f2 \gset
select verifier('F', 'Swend scellé passé : pas actif', not swend_actif_entre(:'M', :'J'));
select nv_swend(:'M', :'J', now() + interval '20 days') as f3 \gset
select verifier('F', 'Swend scellé à venir : actif (dans les deux sens)',
  swend_actif_entre(:'J', :'M') and swend_actif_entre(:'M', :'J'));
update pactes set statut = 'annule' where id = :'f3';
select verifier('F', 'annulé : pas actif', not swend_actif_entre(:'J', :'M'));

-- ===================================================================
-- G. Droits et logique unique
-- ===================================================================
select verifier('G', 'l''app ne lit pas les chats « jamais ouverts » et n''exécute pas les outils internes',
  cs_lire(:'J', 'select count(*)::text from chats_apres_swend_jamais_ouverts') = 'REFUS'
  and not has_function_privilege('authenticated', 'public.swend_actif_entre(uuid, uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.participants_potentiels_chat_apres_swend(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.fermer_chats_apres_nouveau_swend()', 'execute'));
select verifier('G', 'l''app ne peut ni fermer ni rouvrir un chat, ni écrire un message système',
  en_tant_que(:'D', format('update chats_apres_swend set ferme_le = null, motif_fermeture = null where id = %L', :'c5')) <> 'OK'
  and en_tant_que(:'D', format('insert into messages_apres_swend (chat_id, genre, contenu) values (%L, ''systeme'', ''x'')', :'c5')) <> 'OK'
  and nv_etat(:'c5') = 'ferme:nouveau_swend|systeme=1');
select verifier('G', 'moteur et fermeture : une seule définition des participants potentiels',
  (select bool_and(prosrc like '%participants_potentiels_chat_apres_swend%') from pg_proc
   where proname in ('ouvrir_chats_apres_swend', 'fermer_chats_apres_nouveau_swend'))
  and (select prosrc not like '%from remplacants where pacte_id = p.id and selectionne%' from pg_proc
       where proname = 'ouvrir_chats_apres_swend'));
select verifier('G', 'création depuis le chat : renvoie seulement l''identifiant du Swend (D-024)',
  pg_get_function_result('public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb)'::regprocedure) = 'uuid');

select case when ok then 'PASS' else 'FAIL' end as r, scenario, verif, detail from test_resultats order by id;
