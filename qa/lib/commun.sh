#!/bin/bash
# Chemins, configuration et accès Postgres communs à tous les scripts QA.
# À "sourcer" : . "$(dirname "$0")/lib/commun.sh"

QA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$QA_ROOT/.." && pwd)"
set -a; . "$QA_ROOT/config.env"; set +a

QA_API_URL="http://127.0.0.1:$QA_API_PORT"
QA_APP_URL="http://127.0.0.1:$QA_APP_PORT"
QA_PG_DATA="$QA_DATA_DIR/pg"
QA_PG_SOCKET="$QA_DATA_DIR/run"
QA_LOGS="$QA_DATA_DIR/logs"
QA_WORK="$QA_ROOT/.work"
QA_BIN="$QA_ROOT/.bin"
export QA_ROOT REPO_ROOT QA_API_URL QA_APP_URL QA_PG_DATA QA_PG_SOCKET QA_LOGS QA_WORK QA_BIN

if [ -z "$PG_BIN" ]; then
  if command -v initdb >/dev/null 2>&1; then PG_BIN="$(dirname "$(command -v initdb)")";
  else PG_BIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)"; fi
fi
export PG_BIN

# Postgres refuse de tourner en root : on passe alors par l'utilisateur
# système "postgres".
qa_pg_cmd() {
  if [ "$(id -u)" = "0" ]; then su postgres -s /bin/bash -c "$*"; else bash -c "$*"; fi
}

# psql sur la base locale du banc (socket local uniquement).
qa_psql() {
  local base="$1"; shift
  "$PG_BIN/psql" -h "$QA_PG_SOCKET" -p "$QA_PG_PORT" -U postgres -d "$base" -X -q "$@"
}

qa_titre() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
qa_erreur() { printf '\033[31mERREUR : %s\033[0m\n' "$*" >&2; }
