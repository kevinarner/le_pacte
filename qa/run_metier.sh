#!/bin/bash
# Tests métier rapides, sans navigateur :
#  - garde-fou production (autotest) ;
#  - règles serveur en SQL sur une base neuve (transitions, concurrence,
#    RLS, confidentialité, téléphone, lu/non lu, migrations) ;
#  - logique Dart (normalisation, liens Messages/WhatsApp, textes, rôles).
#   qa/run_metier.sh            tout
#   qa/run_metier.sh sql|dart   une partie seulement
. "$(dirname "$0")/lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1
PARTIE="${1:-tout}"
DEBUT=$(date +%s)
RAPPORT="$(mktemp)"; ARTEFACTS="$QA_ROOT/artifacts/$(date +%Y%m%d-%H%M%S)-metier"
note() { tee -a "$RAPPORT"; }

qa_titre "Garde-fou production"
qa_garde_fou_autotest | note

if [ "$PARTIE" = tout ] || [ "$PARTIE" = sql ]; then
  "$QA_ROOT/stack.sh" start >/dev/null || { qa_erreur "pile QA indisponible"; exit 1; }
  qa_titre "Base neuve $QA_DB_METIER (schéma + migrations, idempotence)"
  if "$QA_ROOT/db/construire_base.sh" "$QA_DB_METIER" --rejouer; then
    echo "PASS — [migrations] toutes les migrations s'appliquent, et se rejouent sans erreur" | note
  else
    echo "FAIL — [migrations] application des migrations (voir $QA_LOGS/migration.log)" | note; exit 1
  fi
  for f in "$QA_ROOT"/metier/sql/*.sql; do
    suite="$(basename "$f" .sql | sed 's/^[0-9]*_//')"
    qa_titre "SQL : $suite"
    if ! qa_psql "$QA_DB_METIER" -v ON_ERROR_STOP=1 -f "$f" > "$QA_LOGS/sql_$suite.log" 2>&1; then
      echo "FAIL — [$suite] le script s'est arrêté : $(grep -m1 ERROR "$QA_LOGS/sql_$suite.log")" | note
      continue
    fi
    qa_psql "$QA_DB_METIER" -tA -F '|' -c "select case when ok then 'PASS' else 'FAIL' end, scenario, verif, coalesce(detail, '') from test_resultats order by id" \
      | awk -F'|' -v s="$suite" '{ d = ($4 != "" && $1 == "FAIL") ? " — " $4 : ""; print $1 " — [" s "] " $2 " : " $3 d }' | note
  done
  qa_titre "SQL : concurrence (connexions réelles simultanées)"
  "$QA_ROOT/metier/concurrence.sh" "$QA_DB_METIER" | note
  qa_titre "SQL : migration téléphone sur données existantes"
  "$QA_ROOT/metier/rattrapage.sh" | note
fi

if [ "$PARTIE" = tout ] || [ "$PARTIE" = dart ]; then
  qa_titre "Dart : logique de l'app"
  (cd "$REPO_ROOT" && flutter test --reporter json 2>/dev/null) | node "$QA_ROOT/metier/dart_rapport.mjs" | note
fi

NPASS=$(grep -c '^PASS' "$RAPPORT"); NFAIL=$(grep -c '^FAIL' "$RAPPORT")
DUREE=$(( $(date +%s) - DEBUT ))
qa_titre "Résumé — tests métier"
echo "$NPASS PASS"; echo "$NFAIL FAIL"; echo "durée totale : $((DUREE / 60)) min $((DUREE % 60)) s"
if [ "$NFAIL" != 0 ]; then
  mkdir -p "$ARTEFACTS"; grep '^FAIL' "$RAPPORT" > "$ARTEFACTS/echecs.txt"; cp "$RAPPORT" "$ARTEFACTS/rapport.txt"
  cp "$QA_LOGS"/sql_*.log "$ARTEFACTS/" 2>/dev/null
  echo "Échecs et journaux : $ARTEFACTS"
fi
rm -f "$RAPPORT"
[ "$NFAIL" = 0 ]
