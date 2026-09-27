#!/bin/bash
# GARDE-FOU PRODUCTION. Sourcé par tous les scripts du banc QA.
# Le banc ne doit JAMAIS pouvoir parler à Supabase production : au moindre
# doute (adresse non locale, référence du projet de production, clé de
# service présente dans l'environnement), on refuse de démarrer.

# Référence du projet de production, lue dans le code de l'app
# (lib/constants.dart : https://<ref>.supabase.co).
qa_ref_production() {
  grep -o 'https://[a-z0-9]*\.supabase\.co' "$REPO_ROOT/lib/constants.dart" | head -1 \
    | sed -E 's#https://([a-z0-9]*)\.supabase\.co#\1#'
}

qa_garde_fou() {
  local ref; ref="$(qa_ref_production)"
  if [ -z "$ref" ]; then
    qa_erreur "garde-fou : référence de production introuvable dans lib/constants.dart — arrêt par prudence."
    return 1
  fi
  # 1. L'API visée doit être locale.
  if ! [[ "$QA_API_URL" =~ ^http://(127\.0\.0\.1|localhost):[0-9]+$ ]]; then
    qa_erreur "garde-fou : QA_API_URL='$QA_API_URL' n'est pas une adresse locale. Refus de démarrer."
    return 1
  fi
  # 2. Aucune variable de configuration ou d'environnement ne doit pointer
  #    vers Supabase ou vers le projet de production.
  local nom valeur
  for nom in $(compgen -e); do
    case "$nom" in
      QA_*|SUPABASE*|DATABASE_URL|PGHOST|PGHOSTADDR|PGSERVICE|POSTGRES*|API_URL|ANON_KEY|SERVICE_ROLE*) ;;
      *) continue ;;
    esac
    valeur="${!nom}"
    if [[ "$valeur" == *"$ref"* || "$valeur" == *".supabase.co"* || "$valeur" == *"supabase.com"* || "$valeur" == *"pooler.supabase"* ]]; then
      qa_erreur "garde-fou : la variable $nom pointe vers Supabase ou la production. Refus de démarrer."
      return 1
    fi
  done
  # 3. Aucune clé de service dans l'environnement du banc.
  if compgen -e | grep -qi 'service_role'; then
    qa_erreur "garde-fou : une variable *SERVICE_ROLE* est définie. Le banc n'en a jamais besoin. Refus de démarrer."
    return 1
  fi
  # 4. Postgres uniquement en local.
  if [ -n "$PGHOST" ] && ! [[ "$PGHOST" =~ ^(/|127\.0\.0\.1$|localhost$) ]]; then
    qa_erreur "garde-fou : PGHOST='$PGHOST' n'est pas local. Refus de démarrer."
    return 1
  fi
  return 0
}

# Vérifie qu'une build web QA ne contient aucune trace de la production
# (adresse du projet, clé anonyme de production).
qa_garde_fou_build() {
  local dossier="$1" ref cle
  ref="$(qa_ref_production)"
  cle="$(grep -A1 'supabaseAnonKey' "$REPO_ROOT/lib/constants.dart" | grep -o "'eyJ[^']*'" | tr -d "'" | cut -c1-60)"
  if grep -rqs -e "$ref" -e ".supabase.co" "$dossier" || { [ -n "$cle" ] && grep -rqsF "$cle" "$dossier"; }; then
    qa_erreur "garde-fou : la build QA ($dossier) contient l'adresse ou la clé de production. Build rejetée."
    return 1
  fi
  return 0
}

# Autotest : le garde-fou doit bien refuser chaque cas dangereux.
qa_garde_fou_autotest() {
  local ref ok=0 ko=0 tmp
  ref="$(qa_ref_production)"
  _cas() { # description, commande (doit échouer)
    if ( eval "$2" ) >/dev/null 2>&1; then echo "FAIL — garde-fou : $1 (accepté à tort)"; ko=$((ko+1));
    else echo "PASS — garde-fou : $1"; ok=$((ok+1)); fi
  }
  _cas "refuse une API de production" "QA_API_URL=https://$ref.supabase.co qa_garde_fou"
  _cas "refuse une API non locale" "QA_API_URL=http://10.0.0.5:8850 qa_garde_fou"
  _cas "refuse SUPABASE_URL de production dans l'environnement" "export SUPABASE_URL=https://$ref.supabase.co; qa_garde_fou"
  _cas "refuse DATABASE_URL vers Supabase" "export DATABASE_URL=postgres://u:p@db.$ref.supabase.co:5432/postgres; qa_garde_fou"
  _cas "refuse une clé de service dans l'environnement" "export SUPABASE_SERVICE_ROLE_KEY=x; qa_garde_fou"
  _cas "refuse PGHOST distant" "export PGHOST=db.example.com; qa_garde_fou"
  tmp="$(mktemp -d)"; echo "const u='https://$ref.supabase.co';" > "$tmp/main.dart.js"
  _cas "rejette une build contenant l'adresse de production" "qa_garde_fou_build '$tmp'"
  rm -rf "$tmp"
  if ( qa_garde_fou ) >/dev/null 2>&1; then echo "PASS — garde-fou : accepte la configuration locale du banc"; ok=$((ok+1));
  else echo "FAIL — garde-fou : refuse la configuration locale du banc"; ko=$((ko+1)); fi
  [ "$ko" = 0 ]
}
