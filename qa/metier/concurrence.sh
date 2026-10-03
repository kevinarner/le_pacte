#!/bin/bash
# Concurrence réelle : acceptations simultanées sur des connexions Postgres
# séparées (après sql/10_imprevu.sql, qui fournit nouveau_swend, etc.).
#   qa/metier/concurrence.sh <base>
. "$(dirname "$0")/../lib/commun.sh"
BASE="$1"; COURSES="${QA_COURSES:-30}"
P() { qa_psql "$BASE" -tA "$@"; }
E=00000000-0000-0000-0000-00000000000e
D=00000000-0000-0000-0000-00000000000d
K=00000000-0000-0000-0000-00000000000a
C=00000000-0000-0000-0000-00000000000c
resultat() { if [ "$2" = "1" ]; then echo "PASS — [concurrence] $1"; else echo "FAIL — [concurrence] $1 — $3"; fi; }

preparer() { # Kevin et Camille sollicités côté Eliot
  P <<SQL | tail -1
select nouveau_swend() as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'c')) \gset
select :'p' || ' ' || :'k' || ' ' || :'c';
SQL
}
accepter() { # utilisateur, fiche → vide si OK, sinon le code d'erreur
  P -c "set role authenticated; select set_config('request.jwt.claim.sub', '$1', false); select repondre_demande_remplacement('$2', true);" 2>&1 \
    | grep -oE "place_deja_prise|deja_remplacant_autre_cote|ERROR.*" | head -1 || true
}

# 1. Une acceptation tenue ouverte bloque la seconde, qui perd ensuite.
read p k c <<< "$(preparer)"
( P -c "begin; set local role authenticated; select set_config('request.jwt.claim.sub', '$K', true); select repondre_demande_remplacement('$k', true); select pg_sleep(2); commit;" >/dev/null 2>&1 ) &
sleep 0.4
res=$(accepter $C "$c"); wait
n=$(P -c "select count(*) from remplacants where pacte_id = '$p' and selectionne")
resultat "acceptation en attente de verrou : la seconde perd (place_deja_prise)" "$([[ "$res" == *place_deja_prise* ]] && [ "$n" = 1 ] && echo 1)" "résultat=$res sélectionnés=$n"

# 2. N courses réellement simultanées : toujours exactement un gagnant.
ok=0; detail=""
for i in $(seq 1 "$COURSES"); do
  read p k c <<< "$(preparer)"
  f1=$(mktemp); f2=$(mktemp)
  accepter $K "$k" > "$f1" & accepter $C "$c" > "$f2" & wait
  n=$(P -c "select count(*) from remplacants where pacte_id = '$p' and selectionne")
  perdants=$(cat "$f1" "$f2" | grep -c place_deja_prise); rm -f "$f1" "$f2"
  if [ "$n" = 1 ] && [ "$perdants" = 1 ]; then ok=$((ok+1)); else detail="course $i : sélectionnés=$n perdants=$perdants"; fi
done
resultat "$COURSES courses simultanées : un seul gagnant à chaque fois" "$([ "$ok" = "$COURSES" ] && echo 1)" "$ok/$COURSES — $detail"

# 3. La même personne accepte des deux côtés en même temps : une seule place.
ok=0; detail=""
for i in $(seq 1 $((COURSES / 2))); do
  read p ke kd <<< "$(P <<SQL | tail -1
select nouveau_swend() as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as ke \gset
select ajouter_fiche('$D', :'p', 'destinataire', 'Kevin', '0600000003') as kd \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'ke')) \gset
select en_tant_que('$D', format('select envoyer_demande_remplacement(%L)', :'kd')) \gset
select :'p' || ' ' || :'ke' || ' ' || :'kd';
SQL
)"
  accepter $K "$ke" >/dev/null & accepter $K "$kd" >/dev/null & wait
  nsel=$(P -c "select count(*) from remplacants where pacte_id = '$p' and selectionne")
  statut=$(P -c "select statut from pactes where id = '$p'")
  if [ "$nsel" = 1 ] && [ "$statut" = confirme ]; then ok=$((ok+1)); else detail="essai $i : sélectionnés=$nsel statut=$statut"; fi
done
resultat "même personne des deux côtés en même temps : une seule place, Swend toujours scellé" "$([ "$ok" = $((COURSES / 2)) ] && echo 1)" "$ok/$((COURSES / 2)) — $detail"

# 4. Rappels (D-021) : plusieurs exécutions simultanées du moteur à la même
#    échéance → chaque personne reçoit le rappel une seule fois.
ok=0; detail=""
for i in $(seq 1 10); do
  p=$(P -c "select swend_rappels()")
  for j in 1 2 3; do P -c "select envoyer_rappels_dus('2037-10-05 16:00+00')" >/dev/null 2>&1 & done; wait
  n=$(P -c "select count(*) from notifications_log where data->>'type' = 'rappel' and data->>'pacte_id' = '$p'")
  if [ "$n" = 2 ]; then ok=$((ok+1)); else detail="essai $i : $n push au lieu de 2"; fi
done
resultat "rappels : 3 exécutions simultanées du moteur, jamais de push en double" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 5. Annulation (D-022) pendant qu'une personne accepte : jamais d'état
#    incohérent. Soit l'acceptation passe d'abord (Kevin remplaçant, puis
#    prévenu de l'annulation), soit l'annulation d'abord (demande close).
ok=0; detail=""
for i in $(seq 1 10); do
  read p k <<< "$(P <<SQL | tail -1
select swend_annulable() as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k';
SQL
)"
  n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
  accepter $K "$k" >/dev/null &
  P -c "set role authenticated; select set_config('request.jwt.claim.sub', '$E', false); select annuler_swend('$p');" >/dev/null 2>&1 &
  wait
  etat=$(P -c "select p.statut || '|' || coalesce(r.demande_statut, 'null') || '|' || r.selectionne from pactes p join remplacants r on r.pacte_id = p.id where p.id = '$p'")
  push=$(P -c "select string_agg(titre, ' + ') from notifications_log where id > $n0 and profile_id = '$K' and (titre = 'Le Swend est annulé' or titre like 'La demande n%')")
  if { [ "$etat" = "annule|acceptee|true" ] && [ "$push" = "Le Swend est annulé" ]; } \
     || { [ "$etat" = "annule|cloturee|false" ] && [[ "$push" == "La demande n"* ]] && [[ "$push" != *" + "* ]]; }; then
    ok=$((ok+1)); else detail="essai $i : état=$etat push=$push"; fi
done
resultat "annulation et acceptation simultanées : Swend annulé, Kevin prévenu une seule fois, jamais d'état incohérent" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 6. Gel à H (D-023a) : une acceptation commencée juste avant H et tenue
#    ouverte pendant que le moteur passe à H. Le moteur attend le verrou, puis
#    voit la place prise : Kevin reste sélectionné, aucune push « La demande
#    n'est plus d'actualité », événement de fin après l'acceptation.
read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '1500 milliseconds') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k';
SQL
)"
n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
( P -c "begin; set local role authenticated; select set_config('request.jwt.claim.sub', '$K', true); select repondre_demande_remplacement('$k', true); select pg_sleep(2.5); commit;" >/dev/null 2>&1 ) &
sleep 1.8
P -c "select figer_swends_passes()" >/dev/null 2>&1; wait
etat=$(P -c "select statut_fiche('$k') || '|' || g_fige('$p') || '|' || g_codes('$k')")
push=$(P -c "select count(*) from notifications_log where id > $n0 and profile_id = '$K' and titre like 'La demande n%'")
resultat "gel à H : acceptation commencée avant H, moteur en attente du verrou → Kevin garde la place, aucune push de clôture" \
  "$([ "$etat" = "acceptee+sel|traite|demande_envoyee,demande_acceptee,swend_commence" ] && [ "$push" = 0 ] && echo 1)" "état=$etat push=$push"

# 7. Courses réelles à H : acceptation et moteur lancés ensemble au moment
#    exact de H. Deux issues seulement : acceptée avant H (place prise, pas de
#    push de clôture), ou refusée (swend_passe / place_deja_prise) et demande
#    close avec une seule push. Jamais les deux.
ok=0; detail=""
for i in $(seq 1 10); do
  read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '700 milliseconds') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k';
SQL
)"
  n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
  sleep 0.5
  f1=$(mktemp)
  accepter $K "$k" > "$f1" & P -c "select figer_swends_passes()" >/dev/null 2>&1 &
  sleep 0.4; P -c "select figer_swends_passes()" >/dev/null 2>&1; wait
  err=$(grep -oE "swend_passe|place_deja_prise" "$f1" | head -1); rm -f "$f1"
  etat=$(P -c "select statut_fiche('$k') || '|' || g_fige('$p')")
  push=$(P -c "select count(*) from notifications_log where id > $n0 and profile_id = '$K' and titre like 'La demande n%'")
  if { [ "$etat" = "acceptee+sel|traite" ] && [ -z "$err" ] && [ "$push" = 0 ]; } \
     || { [ "$etat" = "cloturee|traite" ] && [ -n "$err" ] && [ "$push" = 1 ]; }; then
    ok=$((ok+1)); else detail="essai $i : état=$etat erreur=$err push=$push"; fi
done
resultat "gel à H : 10 courses acceptation / moteur au moment de H, toujours une seule issue cohérente" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 8. Gel à H : trois exécutions simultanées du moteur → une seule clôture,
#    une seule push, un seul événement de fin.
ok=0; detail=""
for i in $(seq 1 10); do
  read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '1 hour') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select g_dater(:'p', now() - interval '1 second');
select :'p' || ' ' || :'k';
SQL
)"
  n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
  for j in 1 2 3; do P -c "select figer_swends_passes()" >/dev/null 2>&1 & done; wait
  push=$(P -c "select count(*) from notifications_log where id > $n0 and profile_id = '$K'")
  codes=$(P -c "select g_codes('$k')")
  if [ "$push" = 1 ] && [ "$codes" = "demande_envoyee,demande_cloturee,swend_commence" ]; then ok=$((ok+1)); else detail="essai $i : push=$push événements=$codes"; fi
done
resultat "gel à H : 3 exécutions simultanées du moteur, jamais de doublon" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 9. Chat après le Swend (D-023b) : trois exécutions simultanées du moteur à
#    l'heure d'ouverture → un seul chat, trois participants, trois push.
#    (Outils de sql/99b_chat_apres_swend.sql ; Swends datés en 2032.)
T=00000000-0000-0000-0000-00000000000b
ok=0; detail=""
for i in $(seq 1 10); do
  h="2032-01-01 12:00 Europe/Paris"
  p=$(P <<SQL | tail -1
select cs_swend('$h'::timestamptz + interval '$i days') as p \gset
select cs_fiche(:'p', 'initiateur', 'Thomas', '0600000005', 'selectionne') \gset
select figer_swends_passes('$h'::timestamptz + interval '$i days 1 minute');
select :'p';
SQL
)
  n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
  for j in 1 2 3; do P -c "select ouvrir_chats_apres_swend('$h'::timestamptz + interval '$i days 3 hours')" >/dev/null 2>&1 & done; wait
  chats=$(P -c "select count(*) from chats_apres_swend where pacte_id = '$p'")
  parts=$(P -c "select count(*) from participants_chat_apres_swend a join chats_apres_swend c on c.id = a.chat_id where c.pacte_id = '$p'")
  push=$(P -c "select count(*) from notifications_log where id > $n0 and data->>'pacte_id' = '$p'")
  if [ "$chats" = 1 ] && [ "$parts" = 3 ] && [ "$push" = 3 ]; then ok=$((ok+1)); else detail="essai $i : chats=$chats participants=$parts push=$push"; fi
done
resultat "chat après le Swend : 3 moteurs simultanés, un seul chat, une seule ouverture" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 10-12. Nouveau Swend (D-023c). Outils de sql/99e_nouveau_swend.sql
#    (nv_swend, nv_remplacant, nv_ouvrir, nv_sceller) ; personnes propres.
P >/dev/null <<'SQL'
insert into profiles (id, prenom, nom, telephone) values
 ('00000000-0000-0000-0000-000000000401', 'Oscar', 'O', '0614000001'),
 ('00000000-0000-0000-0000-000000000402', 'Rose', 'R', '0614000002'),
 ('00000000-0000-0000-0000-000000000403', 'Simon', 'S', '0614000003'),
 ('00000000-0000-0000-0000-000000000404', 'Tina', 'T', '0614000004'),
 ('00000000-0000-0000-0000-000000000405', 'Ugo', 'U', '0614000005')
on conflict do nothing;
SQL
O=00000000-0000-0000-0000-000000000401; R=00000000-0000-0000-0000-000000000402
S=00000000-0000-0000-0000-000000000403; TI=00000000-0000-0000-0000-000000000404
U=00000000-0000-0000-0000-000000000405

# 10. Chat à 3 (Oscar, Rose, Simon remplaçant de Rose) : deux nouveaux Swends
#     de paires différentes scellés en même temps (une fois avec une
#     transaction tenue ouverte) → chat fermé, un seul message système.
ok=0; detail=""
for i in $(seq 1 10); do
  read ch na nb <<< "$(P <<SQL | tail -1
select nv_swend('$O', '$R', now() - interval '20 days' + interval '$i minutes') as s \gset
select nv_remplacant(:'s', 'destinataire', '$S') \gset
select nv_ouvrir(:'s') as ch \gset
select nv_swend('$O', '$R', now() + interval '$((40 + i)) days', 'enAttenteChoixDateDestinataire') as na \gset
select nv_swend('$S', '$O', now() + interval '$((60 + i)) days', 'enAttenteChoixDateDestinataire') as nb \gset
select :'ch' || ' ' || :'na' || ' ' || :'nb';
SQL
)"
  if [ "$i" = 1 ]; then
    ( P -c "begin; select nv_sceller('$na'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
    sleep 0.4; P -c "select nv_sceller('$nb')" >/dev/null 2>&1; wait
  else
    P -c "select nv_sceller('$na')" >/dev/null 2>&1 & P -c "select nv_sceller('$nb')" >/dev/null 2>&1 & wait
  fi
  etat=$(P -c "select nv_etat('$ch')")
  scelles=$(P -c "select count(*) from pactes where id in ('$na', '$nb') and scelle_le is not null")
  if [ "$etat" = "ferme:nouveau_swend|systeme=1" ] && [ "$scelles" = 2 ]; then ok=$((ok+1)); else detail="essai $i : $etat, scellés=$scelles"; fi
done
resultat "nouveau Swend : 2 scellements simultanés sur le même chat, une seule fermeture, un seul message" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 11. Chat pas encore ouvert : le moteur d'ouverture et un scellement entre
#     les deux personnes lancés ensemble (une fois avec le scellement tenu
#     ouvert). Deux issues seulement : jamais ouvert, ou ouvert puis fermé
#     avec un message système. Jamais un chat resté ouvert.
ok=0; detail=""; issues=""
for i in $(seq 1 10); do
  read s n <<< "$(P <<SQL | tail -1
select nv_swend('$TI', '$U', now() - interval '1 hour' - interval '$i minutes') as s \gset
select nv_ouvrir(:'s') \gset
select nv_swend('$U', '$TI', now() + interval '$((40 + i)) days', 'enAttenteChoixDateDestinataire') as n \gset
select :'s' || ' ' || :'n';
SQL
)"
  if [ "$i" = 1 ]; then
    ( P -c "begin; select nv_sceller('$n'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
    sleep 0.4; P -c "select ouvrir_chats_apres_swend(now() + interval '2 days')" >/dev/null 2>&1; wait
  else
    P -c "select nv_sceller('$n')" >/dev/null 2>&1 & P -c "select ouvrir_chats_apres_swend(now() + interval '2 days')" >/dev/null 2>&1 & wait
  fi
  P -c "select ouvrir_chats_apres_swend(now() + interval '2 days')" >/dev/null 2>&1
  etat=$(P -c "select coalesce((select nv_etat(id) from chats_apres_swend where pacte_id = '$s'), 'jamais')")
  case "$etat" in
    jamais|"ferme:nouveau_swend|systeme=1") ok=$((ok+1)); issues="$issues $etat" ;;
    *) detail="essai $i : $etat" ;;
  esac
done
resultat "chat pas encore ouvert : moteur et scellement simultanés, jamais un chat resté ouvert" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 12. « Faire un nouveau Swend » : les deux personnes d'un chat créent en
#     même temps un Swend l'une avec l'autre → un seul Swend, l'autre refusé
#     (swend_deja_en_cours).
creer() { # utilisateur, chat, participant → id du Swend ou code d'erreur
  P -c "set role authenticated; select set_config('request.jwt.claim.sub', '$1', false); select creer_swend_depuis_chat('$2', '$3', 'diner', to_jsonb(array[now() + interval '20 days']), '00000000-0000-0000-0000-0000000000aa', '[]');" 2>&1 \
    | grep -vx "$1" | grep -oE "swend_deja_en_cours|ERROR.*|^[0-9a-f-]{36}$" | head -1 || true
}
ok=0; detail=""
for i in $(seq 1 10); do
  read ch pr po <<< "$(P <<SQL | tail -1
update pactes set statut = 'annule' where statut <> 'annule' and scelle_le is null
  and ((initiateur_id = '$O' and destinataire_id = '$U') or (initiateur_id = '$U' and destinataire_id = '$O'));
select nv_swend('$O', '$U', now() - interval '30 days' + interval '$i minutes') as s \gset
select nv_ouvrir(:'s') as ch \gset
select :'ch' || ' ' || nv_participant(:'ch', '$U') || ' ' || nv_participant(:'ch', '$O');
SQL
)"
  f1=$(mktemp); f2=$(mktemp)
  creer $O "$ch" "$pr" > "$f1" & creer $U "$ch" "$po" > "$f2" & wait
  crees=$(cat "$f1" "$f2" | grep -cE '^[0-9a-f-]{36}$'); refus=$(cat "$f1" "$f2" | grep -c swend_deja_en_cours)
  actifs=$(P -c "select count(*) from pactes where statut = 'enAttenteChoixDateDestinataire'
    and ((initiateur_id = '$O' and destinataire_id = '$U') or (initiateur_id = '$U' and destinataire_id = '$O'))")
  rm -f "$f1" "$f2"
  if [ "$crees" = 1 ] && [ "$refus" = 1 ] && [ "$actifs" = 1 ]; then ok=$((ok+1)); else detail="essai $i : créés=$crees refusés=$refus actifs=$actifs"; fi
done
resultat "nouveau Swend : créations simultanées par les deux personnes, un seul Swend en cours" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 13. « Créer un Swend » depuis l'accueil (INSERT de l'app) : les deux
#     personnes s'invitent en même temps → un seul Swend en cours, l'autre
#     refusé (swend_deja_en_cours). Règle globale, comme depuis le chat.
accueil() { # utilisateur, numéro de l'autre → id du Swend ou code d'erreur
  P -c "set role authenticated; select set_config('request.jwt.claim.sub', '$1', false); insert into pactes (type, statut, dates_proposees, restaurant_id, initiateur_id, initiateur_nom, destinataire_nom, destinataire_telephone) values ('diner', 'enAttenteChoixDateDestinataire', to_jsonb(array[now() + interval '20 days']), '00000000-0000-0000-0000-0000000000aa', '$1', 'Initiateur', 'Destinataire', '$2') returning id;" 2>&1 \
    | grep -vx "$1" | grep -oE "swend_deja_en_cours|ERROR.*|^[0-9a-f-]{36}$" | head -1 || true
}
ok=0; detail=""
for i in $(seq 1 10); do
  P -c "update pactes set statut = 'annule' where statut <> 'annule'
    and ((initiateur_id = '$R' and destinataire_id = '$S') or (initiateur_id = '$S' and destinataire_id = '$R'))" >/dev/null
  f1=$(mktemp); f2=$(mktemp)
  accueil $R 0614000003 > "$f1" & accueil $S 0614000002 > "$f2" & wait
  crees=$(cat "$f1" "$f2" | grep -cE '^[0-9a-f-]{36}$'); refus=$(cat "$f1" "$f2" | grep -c swend_deja_en_cours)
  actifs=$(P -c "select count(*) from pactes where statut = 'enAttenteChoixDateDestinataire'
    and ((initiateur_id = '$R' and destinataire_id = '$S') or (initiateur_id = '$S' and destinataire_id = '$R'))")
  rm -f "$f1" "$f2"
  if [ "$crees" = 1 ] && [ "$refus" = 1 ] && [ "$actifs" = 1 ]; then ok=$((ok+1)); else detail="essai $i : créés=$crees refusés=$refus actifs=$actifs"; fi
done
resultat "accueil : créations simultanées pour la même paire, un seul Swend en cours" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"
