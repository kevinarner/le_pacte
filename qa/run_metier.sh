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
  qa_titre "Parité de schéma avec la production (avant tout test)"
  "$QA_ROOT/metier/parite_schema.sh" "$QA_DB_METIER" | note
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
  # Référence Europe/Paris de PostgreSQL (tzdata du serveur) pour le test
  # croisé de heure_paris_test.dart : chaque créneau (12:00-13:45,
  # 19:00-21:45, 18:00 et 10:00 des rappels / du chat) de chaque jour,
  # 2026-2029 (couverture des données de fuseau de l'app).
  REFERENCE_TZ="$(mktemp)"
  if "$QA_ROOT/stack.sh" start >/dev/null 2>&1; then
    qa_psql postgres -tA -F $'\t' -c "select to_char(j + c.h, 'YYYY-MM-DD HH24:MI'),
        to_char((j + c.h) at time zone 'Europe/Paris' at time zone 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"')
      from generate_series('2026-01-01'::timestamp, '2029-12-31', interval '1 day') j,
           (select '12:00'::time + m * interval '15 minutes' h from generate_series(0, 7) m
            union all select '19:00'::time + m * interval '15 minutes' from generate_series(0, 11) m
            union all select unnest(array['18:00'::time, '10:00'::time])) c" > "$REFERENCE_TZ"
  fi
  [ -s "$REFERENCE_TZ" ] || echo "FAIL — [dart] référence Europe/Paris de PostgreSQL non générée" | note
  # Toute la suite Dart, appareil en UTC, à Paris, à New York et à Auckland :
  # aucun résultat ne doit dépendre du fuseau de l'appareil (R2).
  for tz in UTC Europe/Paris America/New_York Pacific/Auckland; do
    qa_titre "Dart : logique de l'app (appareil TZ=$tz)"
    (cd "$REPO_ROOT" && TZ="$tz" SWEND_TZ_REFERENCE="$( [ -s "$REFERENCE_TZ" ] && echo "$REFERENCE_TZ")" \
       flutter test --reporter json 2>/dev/null) | node "$QA_ROOT/metier/dart_rapport.mjs" "TZ=$tz" | note
  done
  rm -f "$REFERENCE_TZ"
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
