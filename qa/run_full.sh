#!/bin/bash
# Régression complète : tests métier puis tous les scénarios E2E.
#   qa/run_full.sh            métier + E2E
#   qa/run_full.sh --e2e      E2E seulement
. "$(dirname "$0")/lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1
debut=$SECONDS
metier="non lancé"; e2e="FAIL"; statut=0
if [ "$1" != "--e2e" ]; then
  if "$QA_ROOT/run_metier.sh"; then metier="PASS"; else metier="FAIL"; statut=1; fi
fi
"$QA_ROOT/stack.sh" start >/dev/null || exit 1
"$QA_ROOT/app/construire_app.sh" || exit 1
if (cd "$QA_ROOT" && node e2e/run.mjs --suite full); then e2e="PASS"; else statut=1; fi
duree=$((SECONDS - debut))
echo
echo "== Bilan de la régression complète"
echo "métier : $metier"
echo "E2E    : $e2e"
printf 'durée  : %d min %02d s\n' $((duree / 60)) $((duree % 60))
[ $statut = 0 ] && echo "RÉSULTAT : PASS" || echo "RÉSULTAT : FAIL (voir qa/artifacts/)"
exit $statut
