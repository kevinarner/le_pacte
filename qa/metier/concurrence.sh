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
  for j in 1 2 3; do P -c "select envoyer_rappels_dus('2026-10-05 16:00+00')" >/dev/null 2>&1 & done; wait
  n=$(P -c "select count(*) from notifications_log where data->>'type' = 'rappel' and data->>'pacte_id' = '$p'")
  if [ "$n" = 2 ]; then ok=$((ok+1)); else detail="essai $i : $n push au lieu de 2"; fi
done
resultat "rappels : 3 exécutions simultanées du moteur, jamais de push en double" "$([ "$ok" = 10 ] && echo 1)" "$ok/10 — $detail"
