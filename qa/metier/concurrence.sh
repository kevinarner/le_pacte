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

# 5. Annulation (D-022, D-027 lot 2) pendant qu'une personne accepte : jamais
#    d'état incohérent. Soit l'acceptation passe d'abord (Kevin remplaçant ;
#    Eliot, remplacé, ne peut plus annuler : Swend maintenu, aucune push
#    d'annulation), soit l'annulation d'abord (demande close, Kevin prévenu
#    une seule fois « Le Swend est annulé »).
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
  if { [ "$etat" = "confirme|acceptee|true" ] && [ -z "$push" ]; } \
     || { [ "$etat" = "annule|cloturee|false" ] && [ "$push" = "Le Swend est annulé" ]; }; then
    ok=$((ok+1)); else detail="essai $i : état=$etat push=$push"; fi
done
resultat "annulation et acceptation simultanées : remplacé → plus d'annulation, ou annulé → Kevin prévenu une seule fois" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 6. Échéance H-3 (D-027 du 20/10) : une acceptation commencée juste avant
#    H-3 et tenue ouverte pendant que l'échéance passe. L'échéance attend le
#    verrou, puis voit la place prise : le Swend est maintenu, aucune push
#    d'annulation. (Avant le 20/10 : même course au moment de H, gel D-023a ;
#    dès H-3, plus aucune acceptation n'est possible.)
read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '3 hours 1500 milliseconds') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k';
SQL
)"
n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
( P -c "begin; set local role authenticated; select set_config('request.jwt.claim.sub', '$K', true); select repondre_demande_remplacement('$k', true); select pg_sleep(2.5); commit;" >/dev/null 2>&1 ) &
sleep 1.8
P -c "select appliquer_echeances_h3()" >/dev/null 2>&1; wait
etat=$(P -c "select statut_fiche('$k') || '|' || statut || '|' || coalesce(annule_motif, 'aucun') from pactes where id = '$p'")
push=$(P -c "select count(*) from notifications_log where id > $n0 and titre like 'Le Swend est annulé%'")
resultat "échéance H-3 : acceptation commencée avant H-3, échéance en attente du verrou → Swend maintenu, aucune push d'annulation" \
  "$([ "$etat" = "acceptee+sel|confirme|aucun" ] && [ "$push" = 0 ] && echo 1)" "état=$etat push=$push"

# 6 ter. Échéance H-3 : une acceptation demandée avant H-3 mais qui attend le
#    verrou du Swend (tenu par une autre transaction) jusqu'après H-3. L'heure
#    est contrôlée une fois le verrou obtenu, au moment où l'acceptation
#    serait validée : refusée (echeance_h3), demande toujours en attente,
#    puis l'échéance annule le Swend. (Avec un contrôle sur l'heure de début
#    de la requête, elle aurait été acceptée après l'échéance.)
read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '3 hours 1 second') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k';
SQL
)"
n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
( P -c "begin; select 1 from pactes where id = '$p' for update; select pg_sleep(2); commit;" >/dev/null 2>&1 ) &
sleep 0.3
f1=$(mktemp)
debut=$(P -c "select (clock_timestamp() < date_retenue - interval '3 hours')::text from pactes where id = '$p'")
accepter $K "$k" > "$f1"; wait
err=$(grep -oE "echeance_h3" "$f1" | head -1); rm -f "$f1"
etat_avant=$(P -c "select statut_fiche('$k') || '|' || statut from pactes where id = '$p'")
P -c "select appliquer_echeances_h3()" >/dev/null 2>&1
etat=$(P -c "select statut_fiche('$k') || '|' || statut || '|' || coalesce(annule_motif, 'aucun') from pactes where id = '$p'")
push=$(P -c "select count(*) from notifications_log where id > $n0 and profile_id = '$K' and titre = 'Le Swend est annulé'")
resultat "échéance H-3 : acceptation demandée avant H-3 mais en attente du verrou jusqu'après H-3 → refusée (echeance_h3), puis Swend annulé" \
  "$([ "$debut" = true ] && [ "$err" = echeance_h3 ] && [ "$etat_avant" = "envoyee|confirme" ] && [ "$etat" = "cloturee|annule|echeance_h3" ] && [ "$push" = 1 ] && echo 1)" \
  "requête avant H-3=$debut erreur=$err avant échéance=$etat_avant après=$etat push=$push"

# 7. Courses réelles à H-3 : acceptation et échéance lancées ensemble au
#    voisinage immédiat de H-3 (puis une seconde échéance). Deux issues seulement :
#    acceptée avant H-3 (place prise, Swend maintenu, aucune push
#    d'annulation), ou refusée (echeance_h3 / swend_inactif) et Swend annulé
#    (motif echeance_h3), Kevin prévenu une seule fois. Jamais les deux.
ok=0; detail=""; issues=""
for i in $(seq 1 10); do
  read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '3 hours 1 second') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k';
SQL
)"
  n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
  # Lancement de part et d'autre de H-3 selon l'essai (0,6 s à 1,32 s après
  # la création, H-3 à 1 s) : les deux issues sont exercées.
  sleep "$(awk -v i="$i" 'BEGIN { printf "%.2f", 0.52 + 0.08 * i }')"
  f1=$(mktemp)
  accepter $K "$k" > "$f1" & P -c "select appliquer_echeances_h3()" >/dev/null 2>&1 &
  sleep 0.4; P -c "select appliquer_echeances_h3()" >/dev/null 2>&1; wait
  err=$(grep -oE "echeance_h3|swend_inactif" "$f1" | head -1); rm -f "$f1"
  etat=$(P -c "select statut_fiche('$k') || '|' || statut || '|' || coalesce(annule_motif, 'aucun') from pactes where id = '$p'")
  push=$(P -c "select count(*) from notifications_log where id > $n0 and profile_id = '$K' and titre = 'Le Swend est annulé'")
  if { [ "$etat" = "acceptee+sel|confirme|aucun" ] && [ -z "$err" ] && [ "$push" = 0 ]; } \
     || { [ "$etat" = "cloturee|annule|echeance_h3" ] && [ -n "$err" ] && [ "$push" = 1 ]; }; then
    ok=$((ok+1)); issues="$issues ${etat%%|*}"; else detail="essai $i : état=$etat erreur=$err push=$push"; fi
done
acc=$(grep -o "acceptee+sel" <<< "$issues" | wc -l); ann=$(grep -o "cloturee" <<< "$issues" | wc -l)
resultat "échéance H-3 : 10 courses acceptation / échéance au moment de H-3, toujours une seule issue cohérente ($acc acceptées avant H-3, $ann annulées)" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 7 bis. Échéance H-3 : trois exécutions simultanées → une seule annulation,
#    une seule push par personne, un seul chat d'annulation.
ok=0; detail=""
for i in $(seq 1 10); do
  read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '4 hours') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select g_dater(:'p', now() + interval '2 hours');
select :'p' || ' ' || :'k';
SQL
)"
  n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
  for j in 1 2 3; do P -c "select appliquer_echeances_h3()" >/dev/null 2>&1 & done; wait
  push=$(P -c "select string_agg(n::text, ',' order by p) from (select profile_id p, count(*) n from notifications_log where id > $n0 and profile_id in ('$E', '$D', '$K') group by 1) x")
  etat=$(P -c "select statut || '|' || annule_motif || '|' || (select count(*) from chats_apres_swend where pacte_id = '$p') from pactes where id = '$p'")
  if [ "$etat" = "annule|echeance_h3|1" ] && [ "$push" = "1,1,1" ]; then ok=$((ok+1)); else detail="essai $i : état=$etat push=$push"; fi
done
resultat "échéance H-3 : 3 exécutions simultanées, une seule annulation, une push par personne" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 7 ter. Échéance H-3 : le job de l'échéance (chaque minute) et le moteur des
#    rappels (toutes les 5 minutes, qui l'appelle d'abord) au même moment,
#    juste après H-3 → une seule annulation, une push par personne, aucun
#    rappel du Jour J.
P -c "select envoyer_rappels_dus()" >/dev/null 2>&1  # rappels dus d'autres Swends du banc : envoyés avant
ok=0; detail=""
for i in $(seq 1 10); do
  read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '4 hours') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select g_dater(:'p', now() + interval '2 hours 59 minutes 30 seconds');
select :'p' || ' ' || :'k';
SQL
)"
  n0=$(P -c "select coalesce(max(id), 0) from notifications_log")
  P -c "select appliquer_echeances_h3()" >/dev/null 2>&1 & P -c "select envoyer_rappels_dus()" >/dev/null 2>&1 & P -c "select appliquer_echeances_h3()" >/dev/null 2>&1 & wait
  push=$(P -c "select string_agg(n::text, ',' order by p) from (select profile_id p, count(*) n from notifications_log where id > $n0 and profile_id in ('$E', '$D', '$K')
    and (data->>'pacte_id' = '$p' or data->>'remplacant_id' = '$k') group by 1) x")
  rappels=$(P -c "select count(*) from notifications_log where id > $n0 and data->>'type' = 'rappel' and data->>'pacte_id' = '$p'")
  etat=$(P -c "select statut || '|' || annule_motif || '|' || (select count(*) from chats_apres_swend where pacte_id = '$p') from pactes where id = '$p'")
  if [ "$etat" = "annule|echeance_h3|1" ] && [ "$push" = "1,1,1" ] && [ "$rappels" = 0 ]; then ok=$((ok+1)); else detail="essai $i : état=$etat push=$push rappels=$rappels"; fi
done
resultat "échéance H-3 : job de l'échéance et moteur des rappels simultanés, une seule annulation, aucun doublon ni rappel" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"

# 8. Gel à H : trois exécutions simultanées du moteur → une seule clôture,
#    une seule push, un seul événement de fin.
ok=0; detail=""
for i in $(seq 1 10); do
  read p k <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '4 hours') as p \gset
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

# 14-15. « En cas d'imprévu », lot 1 (D-027). Outils de sql/99f.
appeler() { # utilisateur, appel SQL → vide si OK, sinon le code d'erreur (ou l'erreur entière)
  local err code
  err=$(P -c "set role authenticated; select set_config('request.jwt.claim.sub', '$1', false); $2" 2>&1 | grep -m1 ERROR)
  [ -n "$err" ] || return 0
  code=$(grep -oE "place_deja_prise|demande_non_active|aucun_imprevu|personne_indisponible" <<< "$err")
  echo "${code:-$err}"
}

# 14. « Je peux finalement venir » et une acceptation en même temps : l'un ou
#     l'autre, jamais un mélange (place prise sans imprévu, ou imprévu levé
#     avec une demande encore en attente).
ok=0; detail=""
for i in $(seq 1 "$COURSES"); do
  read p k <<< "$(P <<SQL | tail -1
select nouveau_swend() as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k';
SQL
)"
  f1=$(mktemp); f2=$(mktemp)
  appeler $K "select repondre_demande_remplacement('$k', true);" > "$f1" &
  appeler $E "select je_peux_finalement_venir('$p');" > "$f2" & wait
  r1=$(cat "$f1"); r2=$(cat "$f2"); rm -f "$f1" "$f2"
  etat=$(P -c "select statut_fiche('$k') || '|' || exists (select 1 from imprevus_declares where pacte_id = '$p')")
  if { [ -z "$r1" ] && [ "$r2" = place_deja_prise ] && [ "$etat" = "acceptee+sel|true" ]; } \
     || { [ "$r1" = demande_non_active ] && [ -z "$r2" ] && [ "$etat" = "null|false" ]; }; then ok=$((ok+1))
  else detail="course $i : acceptation=${r1:-OK} retour=${r2:-OK} état=$etat"; fi
done
resultat "retour du titulaire et acceptation simultanés : l'un ou l'autre, jamais les deux" "$([ "$ok" = "$COURSES" ] && echo 1)" "$ok/$COURSES — $detail"

# 15. Envoi groupé pendant une acceptation : soit le groupe part avant (et
#     l'acceptation le clôt aussitôt), soit il est refusé en entier ; jamais
#     de demande en attente à côté d'une place prise.
ok=0; detail=""
for i in $(seq 1 "$COURSES"); do
  read p k c t <<< "$(P <<SQL | tail -1
select nouveau_swend() as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Camille', '0600000004') as c \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Tom', '0711223344') as t \gset
select en_tant_que('$E', format('select envoyer_demande_remplacement(%L)', :'k')) \gset
select :'p' || ' ' || :'k' || ' ' || :'c' || ' ' || :'t';
SQL
)"
  f1=$(mktemp); f2=$(mktemp)
  appeler $K "select repondre_demande_remplacement('$k', true);" > "$f1" &
  appeler $E "select * from envoyer_demandes_remplacement(array['$c', '$t']::uuid[]);" > "$f2" & wait
  r1=$(cat "$f1"); r2=$(cat "$f2"); rm -f "$f1" "$f2"
  etat=$(P -c "select statut_fiche('$c') || ',' || statut_fiche('$t') || '|' || (select count(*) from remplacants where pacte_id = '$p' and selectionne)")
  if [ -z "$r1" ] && { { [ -z "$r2" ] && [ "$etat" = "cloturee,cloturee|1" ]; } \
                       || { [ "$r2" = place_deja_prise ] && [ "$etat" = "null,null|1" ]; }; }; then ok=$((ok+1))
  else detail="course $i : acceptation=${r1:-OK} envoi=${r2:-OK} état=$etat"; fi
done
resultat "envoi groupé et acceptation simultanés : tout le groupe ou rien, jamais en attente à côté de la place prise" "$([ "$ok" = "$COURSES" ] && echo 1)" "$ok/$COURSES — $detail"

# 16-18. Annulation et conversations (D-027 lot 2). Outils de
#     sql/99g_annulation_conversations.sql (ac_chat, ac_ferme, ac_annulation)
#     et sql/99e_nouveau_swend.sql (nv_swend, nv_sceller).
code_de() { grep -oE "swend_inactif|remplacement_accepte|demande_non_active|place_deja_prise|swend_passe" <<< "$1" | head -1; }

# 16. Les deux titulaires annulent en même temps : une seule annulation (par
#     le premier), l'autre refusée ; un seul chat d'annulation ; le perdant
#     reçoit une seule push, le gagnant aucune.
ok=0; detail=""
for i in $(seq 1 "$COURSES"); do
  p=$(P -c "select g_swend(now() + interval '2 days')")
  n0=$(P -c "select g_n0()")
  f1=$(mktemp); f2=$(mktemp)
  appeler $E "select annuler_swend('$p');" > "$f1" &
  appeler $D "select annuler_swend('$p');" > "$f2" & wait
  r1=$(code_de "$(cat "$f1")"); r2=$(code_de "$(cat "$f2")"); e1=$(cat "$f1"); e2=$(cat "$f2"); rm -f "$f1" "$f2"
  etat=$(P -c "select ac_annulation('$p') || '|' || (select count(*) from chats_apres_swend where pacte_id = '$p') || '|' || ac_chat('$p')")
  pe=$(P -c "select g_push($n0, '$E')"); pd=$(P -c "select g_push($n0, '$D')")
  if { [ -z "$e1" ] && [ "$r2" = swend_inactif ] && [ "$etat" = "annule|titulaire|Eliot|date|1|annulation" ] \
       && [ -z "$pe" ] && [ "$pd" = "Le Swend est annulé|Eliot ne pourra finalement pas être là." ]; } \
     || { [ -z "$e2" ] && [ "$r1" = swend_inactif ] && [ "$etat" = "annule|titulaire|David|date|1|annulation" ] \
       && [ -z "$pd" ] && [ "$pe" = "Le Swend est annulé|David ne pourra finalement pas être là." ]; }; then ok=$((ok+1))
  else detail="course $i : Eliot=${e1:-OK} David=${e2:-OK} état=$etat pushE=$pe pushD=$pd"; fi
done
resultat "double annulation simultanée : une seule annulation, un seul chat, une push au seul perdant" "$([ "$ok" = "$COURSES" ] && echo 1)" "$ok/$COURSES — $detail"

# 17. Annulation et double remplacement simultanés (Kevin déjà sélectionné
#     côté Eliot ; Camille accepte côté David pendant que David annule) :
#     soit double remplacement (annulation de David refusée), soit annulation
#     par David (acceptation refusée, demande close). Un seul chat, une seule
#     push d'annulation par personne.
ok=0; detail=""; vus=""
for i in $(seq 1 "$COURSES"); do
  read p k c <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '2 days') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select ajouter_fiche('$D', :'p', 'destinataire', 'Camille', '0600000004') as c \gset
select g_rpc('$E', 'envoyer_demande_remplacement', :'k') \gset
select g_rpc('$K', 'repondre_demande_remplacement', :'k', 'true') \gset
select g_rpc('$D', 'envoyer_demande_remplacement', :'c') \gset
select :'p' || ' ' || :'k' || ' ' || :'c';
SQL
)"
  n0=$(P -c "select g_n0()")
  f1=$(mktemp); f2=$(mktemp)
  appeler $C "select repondre_demande_remplacement('$c', true);" > "$f1" &
  appeler $D "select annuler_swend('$p');" > "$f2" & wait
  e1=$(cat "$f1"); e2=$(cat "$f2"); r2=$(code_de "$e2"); rm -f "$f1" "$f2"
  etat=$(P -c "select ac_annulation('$p') || '|' || statut_fiche('$c') || '|' || (select count(*) from chats_apres_swend where pacte_id = '$p')")
  doublons=$(P -c "select count(*) from (select profile_id from notifications_log where id > $n0 and titre like 'Le Swend est annulé%' group by profile_id having count(*) > 1) x")
  if { [ -z "$e1" ] && [ "$r2" = swend_inactif ] && [ "$etat" = "annuleDoubleAbsence|double_remplacement|null|date|acceptee+sel|1" ]; } \
     || { [ -n "$e1" ] && [ -z "$e2" ] && [ "$etat" = "annule|titulaire|David|date|cloturee|1" ]; }; then
    if [ "$doublons" = 0 ]; then ok=$((ok+1)); vus="$vus${etat%%|*} "; else detail="course $i : push en double"; fi
  else detail="course $i : acceptation=${e1:-OK} annulation=${e2:-OK} état=$etat"; fi
done
resultat "annulation et double remplacement simultanés : l'un ou l'autre, un seul chat, aucune push en double" "$([ "$ok" = "$COURSES" ] && echo 1)" "$ok/$COURSES — $detail"

# 18. Annulation et scellement d'un nouveau Swend Eliot–Kevin simultanés (P2)
#     (Kevin sollicité côté Eliot). Dans tous les ordres (une transaction
#     tenue ouverte d'un côté ou de l'autre, ou lancées ensemble), la
#     conversation Eliot–Kevin finit fermée, avec un seul événement.
ok=0; detail=""
for i in $(seq 1 9); do
  read p k s2 <<< "$(P <<SQL | tail -1
select g_swend(now() + interval '2 days') as p \gset
select ajouter_fiche('$E', :'p', 'initiateur', 'Kevin', '0600000003') as k \gset
select g_rpc('$E', 'envoyer_demande_remplacement', :'k') \gset
select nv_swend('$E', '$K', now() + interval '$((80 + i)) days', 'enAttenteChoixDateDestinataire') as s2 \gset
select :'p' || ' ' || :'k' || ' ' || :'s2';
SQL
)"
  case $((i % 3)) in
    0) ( P -c "begin; select nv_sceller('$s2'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
       sleep 0.4; appeler $E "select annuler_swend('$p');" >/dev/null; wait ;;
    1) ( P -c "begin; set local role authenticated; select set_config('request.jwt.claim.sub', '$E', true); select annuler_swend('$p'); select pg_sleep(1.5); commit;" >/dev/null 2>&1 ) &
       sleep 0.4; P -c "select nv_sceller('$s2')" >/dev/null 2>&1; wait ;;
    2) appeler $E "select annuler_swend('$p');" >/dev/null & P -c "select nv_sceller('$s2')" >/dev/null 2>&1 & wait ;;
  esac
  etat=$(P -c "select (select statut from pactes where id = '$p') || '|' || ((select scelle_le from pactes where id = '$s2') is not null) || '|' || ac_ferme('$k') || '|' || (select count(*) from evenements_fil where remplacant_id = '$k' and code = 'fil_ferme')")
  if [ "$etat" = "annule|true|true|1" ]; then ok=$((ok+1)); else detail="essai $i : $etat"; fi
done
resultat "annulation et scellement Eliot–Kevin simultanés : conversation toujours fermée, un seul événement" "$([ "$ok" = 9 ] && echo 1)" "$ok/9 — $detail"
