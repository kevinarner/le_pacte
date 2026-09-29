#!/bin/bash
# Reconstruit une base locale de zéro : schéma initial reconstitué, puis
# toutes les migrations de supabase/migrations/ dans l'ordre, puis les
# fonctions de fixtures QA.
#   qa/db/construire_base.sh <nom_base> [--rejouer]
# --rejouer : ré-applique les migrations prévues pour être relancées (vérifie
#             qu'elles sont bien idempotentes).
. "$(dirname "$0")/../lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1
BASE="$1"; REJOUER="$2"
[ -n "$BASE" ] || { qa_erreur "usage : construire_base.sh <nom_base> [--rejouer]"; exit 1; }

qa_psql postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$BASE' and pid <> pg_backend_pid()" >/dev/null
qa_psql postgres -c "drop database if exists \"$BASE\"" 2>/dev/null
qa_psql postgres -c "create database \"$BASE\"" || exit 1

appliquer() {
  if ! qa_psql "$BASE" -v ON_ERROR_STOP=1 -f "$1" > "$QA_LOGS/migration.log" 2>&1; then
    qa_erreur "échec de $(basename "$1")"; tail -5 "$QA_LOGS/migration.log" >&2; exit 1
  fi
}
appliquer "$QA_ROOT/db/replica/00_schema_initial.sql"
for f in "$REPO_ROOT"/supabase/migrations/*.sql; do appliquer "$f"; done
if [ "$REJOUER" = "--rejouer" ]; then
  for f in "$REPO_ROOT"/supabase/migrations/*_{telephones_phase2,destinataire_a_un_compte,fil_evenements_et_lectures,disponibilite_spontanee_et_notifications,scellage_et_negociation,reservations_suivi,rappels_jour_j,annulation_manuelle,gel_a_h}.sql; do
    appliquer "$f"
  done
fi
appliquer "$QA_ROOT/db/fixtures.sql"
qa_psql "$BASE" -c "notify pgrst, 'reload schema'" >/dev/null 2>&1
exit 0
