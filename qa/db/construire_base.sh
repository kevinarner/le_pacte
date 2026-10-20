#!/bin/bash
# Reconstruit une base locale de zéro : schéma initial reconstitué, puis
# toutes les migrations de supabase/migrations/ dans l'ordre, puis les
# fonctions de fixtures QA.
#   qa/db/construire_base.sh <nom_base> [--rejouer]
#   QA_BASE=avant-D-027-02 qa/db/construire_base.sh <nom_base>   (sans le lot 2)
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
# Même fuseau de session que la production (UTC) : une conversion implicite
# s'y comporte comme en production (R2).
qa_psql postgres -c "alter database \"$BASE\" set timezone to 'UTC'" >/dev/null || exit 1

appliquer() {
  if ! qa_psql "$BASE" -v ON_ERROR_STOP=1 -f "$1" > "$QA_LOGS/migration.log" 2>&1; then
    qa_erreur "échec de $(basename "$1")"; tail -5 "$QA_LOGS/migration.log" >&2; exit 1
  fi
}
# QA_BASE=avant-D-027-02 : la production d'avant le 20/10 (sans la migration
# du lot 2 de D-027, deux fonctions dans leur version de production), pour
# vérifier une app sur les deux bases (D-027 lot 3) ; sans l'échéance H-3.
# QA_BASE=avant-D-027-03 : la production depuis le 20/10 (lot 2 appliqué,
# sans l'échéance H-3 ferme).
exclue() {
  case "${QA_BASE:-}" in
    avant-D-027-02) [[ "$1" == *_annulation_et_conversations.sql || "$1" == *_echeance_h3.sql ]] ;;
    avant-D-027-03) [[ "$1" == *_echeance_h3.sql ]] ;;
    *) return 1 ;;
  esac
}
appliquer "$QA_ROOT/db/replica/00_schema_initial.sql"
for f in "$REPO_ROOT"/supabase/migrations/*.sql; do exclue "$f" || appliquer "$f"; done
if [ "$REJOUER" = "--rejouer" ]; then
  for f in "$REPO_ROOT"/supabase/migrations/*_{telephones_phase2,destinataire_a_un_compte,fil_evenements_et_lectures,disponibilite_spontanee_et_notifications,scellage_et_negociation,reservations_suivi,rappels_jour_j,annulation_manuelle,gel_a_h,confidentialite_telephones,chat_apres_swend,delai_minimum_swend,fuseaux_horaires,nouveau_swend,imprevu_etats_et_actions,annulation_et_conversations,echeance_h3}.sql; do
    exclue "$f" || appliquer "$f"
  done
fi
if [ "${QA_BASE:-}" = "avant-D-027-02" ]; then appliquer "$QA_ROOT/db/production/avant_D-027-02.sql"; fi
appliquer "$QA_ROOT/db/fixtures.sql"
qa_psql "$BASE" -c "notify pgrst, 'reload schema'" >/dev/null 2>&1
exit 0
