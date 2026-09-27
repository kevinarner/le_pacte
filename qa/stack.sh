#!/bin/bash
# Pile locale du banc QA : Postgres, PostgREST, faux Supabase (auth, API,
# temps réel) et serveur de la build web QA. Tout écoute sur 127.0.0.1.
#
#   qa/stack.sh setup    première installation (dépendances Node, PostgREST)
#   qa/stack.sh start    démarre la pile (crée la base au besoin)
#   qa/stack.sh stop     arrête tout
#   qa/stack.sh status   état des services
#   qa/stack.sh reset    reconstruit la base e2e de zéro (schéma + migrations)
#   qa/stack.sh logs     chemins des journaux
. "$(dirname "$0")/lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1

POSTGREST_VERSION=12.2.3
POSTGREST_SHA256=9f71269e61ac3a940281e93ff415760f5957e430e475ba4c3889f3ede7d5527c
RUN="$QA_PG_SOCKET"

port_ouvert() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
attendre_port() {
  for _ in $(seq 1 100); do port_ouvert "$1" && return 0; sleep 0.2; done
  qa_erreur "le port $1 ne répond pas ($2)"; return 1
}
lancer() { # nom, commande...
  local nom="$1"; shift
  nohup setsid "$@" > "$QA_LOGS/$nom.log" 2>&1 < /dev/null &
  echo $! > "$RUN/$nom.pid"
}
arreter() {
  local f="$RUN/$1.pid"
  [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; rm -f "$f"
}

cmd_setup() {
  qa_titre "Dépendances Node (playwright-core, ws)"
  (cd "$QA_ROOT" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-audit --no-fund) || exit 1
  qa_titre "PostgREST $POSTGREST_VERSION"
  mkdir -p "$QA_BIN"
  if [ ! -x "$QA_BIN/postgrest" ]; then
    local archive="$QA_BIN/postgrest.tar.xz"
    curl -sSL --max-time 300 -o "$archive" \
      "https://github.com/PostgREST/postgrest/releases/download/v$POSTGREST_VERSION/postgrest-v$POSTGREST_VERSION-linux-static-x64.tar.xz" || exit 1
    echo "$POSTGREST_SHA256  $archive" | sha256sum -c --quiet || { qa_erreur "empreinte PostgREST incorrecte"; rm -f "$archive"; exit 1; }
    tar xJf "$archive" -C "$QA_BIN" && rm -f "$archive"
  fi
  "$QA_BIN/postgrest" --version
  [ -x "$PG_BIN/initdb" ] || { qa_erreur "Postgres introuvable (PG_BIN=$PG_BIN)"; exit 1; }
  "$PG_BIN/postgres" --version
  echo "Installation terminée."
}

cmd_start() {
  [ -x "$QA_BIN/postgrest" ] && [ -d "$QA_ROOT/node_modules/ws" ] || { qa_erreur "lancer d'abord : qa/stack.sh setup"; exit 1; }
  mkdir -p "$QA_DATA_DIR" "$RUN" "$QA_LOGS"
  [ "$(id -u)" = "0" ] && chown -R postgres "$QA_DATA_DIR"
  chmod 777 "$RUN" "$QA_LOGS"
  if [ ! -f "$QA_PG_DATA/PG_VERSION" ]; then
    qa_titre "Initialisation du cluster Postgres local"
    qa_pg_cmd "'$PG_BIN/initdb' -D '$QA_PG_DATA' -U postgres --auth=trust -E UTF8 >/dev/null" || exit 1
  fi
  if ! qa_pg_cmd "'$PG_BIN/pg_ctl' -D '$QA_PG_DATA' status >/dev/null 2>&1"; then
    qa_pg_cmd "'$PG_BIN/pg_ctl' -D '$QA_PG_DATA' -l '$QA_LOGS/postgres.log' -w start \
      -o \"-p $QA_PG_PORT -k $QA_PG_SOCKET -c listen_addresses=127.0.0.1\"" >/dev/null || exit 1
  fi
  # (Re)construit la base E2E si elle manque ou si le schéma a changé
  # (migrations, réplique, fixtures, script de construction).
  local empreinte fichier_empreinte="$QA_DATA_DIR/base_e2e.empreinte"
  empreinte="$(cat "$REPO_ROOT"/supabase/migrations/*.sql "$QA_ROOT"/db/replica/*.sql \
    "$QA_ROOT/db/fixtures.sql" "$QA_ROOT/db/construire_base.sh" | sha256sum | cut -c1-16)"
  if [ "$(qa_psql postgres -tAc "select count(*) from pg_database where datname = '$QA_DB'")" != "1" ] \
     || [ "$(cat "$fichier_empreinte" 2>/dev/null)" != "$empreinte" ]; then
    qa_titre "Construction de la base $QA_DB (schéma modifié ou absent)"
    "$QA_ROOT/db/construire_base.sh" "$QA_DB" || exit 1
    echo "$empreinte" > "$fichier_empreinte"
    arreter postgrest; sleep 0.5
  fi
  if ! port_ouvert "$QA_PGRST_PORT"; then
    cat > "$QA_DATA_DIR/postgrest.conf" <<CONF
db-uri = "postgres://authenticator:authenticator@127.0.0.1:$QA_PG_PORT/$QA_DB"
db-schemas = "public"
db-anon-role = "anon"
jwt-secret = "$QA_JWT_SECRET"
server-host = "127.0.0.1"
server-port = $QA_PGRST_PORT
db-channel-enabled = true
CONF
    lancer postgrest "$QA_BIN/postgrest" "$QA_DATA_DIR/postgrest.conf"
    attendre_port "$QA_PGRST_PORT" postgrest || exit 1
  fi
  if ! port_ouvert "$QA_API_PORT"; then
    lancer faux_supabase node "$QA_ROOT/stack/faux_supabase.mjs"
    attendre_port "$QA_API_PORT" faux_supabase || exit 1
    attendre_port "$QA_APP_PORT" app || exit 1
  fi
  echo "Pile QA démarrée — API $QA_API_URL, app $QA_APP_URL (Postgres :$QA_PG_PORT, PostgREST :$QA_PGRST_PORT)"
}

cmd_stop() {
  arreter faux_supabase; arreter postgrest
  qa_pg_cmd "'$PG_BIN/pg_ctl' -D '$QA_PG_DATA' -m fast stop >/dev/null 2>&1"
  echo "Pile QA arrêtée."
}

cmd_status() {
  local s
  for s in "Postgres:$QA_PG_PORT" "PostgREST:$QA_PGRST_PORT" "API:$QA_API_PORT" "App:$QA_APP_PORT"; do
    if port_ouvert "${s#*:}"; then echo "OK   ${s%%:*} (127.0.0.1:${s#*:})"; else echo "--   ${s%%:*} arrêté"; fi
  done
}

cmd_reset() {
  qa_titre "Reconstruction de la base $QA_DB"
  rm -f "$QA_DATA_DIR/base_e2e.empreinte"
  cmd_start >/dev/null && echo "Base $QA_DB reconstruite."
}

case "$1" in
  setup) cmd_setup ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  reset) cmd_reset ;;
  logs) echo "Journaux : $QA_LOGS"; ls -1 "$QA_LOGS" 2>/dev/null ;;
  *) echo "usage : qa/stack.sh setup|start|stop|status|reset|logs"; exit 1 ;;
esac
