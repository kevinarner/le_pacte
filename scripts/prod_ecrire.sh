#!/bin/bash
# PORTE UNIQUE des écritures en production Swend.
#
#   scripts/prod_ecrire.sh <ID> <empreinte-12>              applique le paquet
#   scripts/prod_ecrire.sh <ID> <empreinte-12> --rollback   exécute son rollback
#
# <empreinte-12> = les 12 premiers caractères de l'empreinte annoncée avec le
# paquet au moment du « Go <ID> » (scripts/paquet_controler.sh <ID>). Elle
# apparaît dans la demande d'approbation de Claude Code : le fondateur
# vérifie que c'est bien celle qu'il a validée.
#
# Refuse, avant tout accès réseau, si : paquet mal formé, artefact modifié
# (SHA-256), paquet ou garde-fous non commités, pas de Go enregistré pour
# cette empreinte, session qui n'est pas « Swend – écriture prod »
# (SWEND_SESSION_ECRITURE=1), paquet déjà appliqué.
# Ne lit, n'affiche ni ne journalise aucun identifiant : l'authentification
# est ajoutée hors de la session par le proxy de l'environnement.
# Format et limites : supabase/changements/README.md.
set -euo pipefail
. "$(dirname "$0")/lib/paquet.sh"

[ $# -ge 2 ] || paquet_refus "usage : scripts/prod_ecrire.sh <ID> <empreinte-12> [--rollback]"
ID="$1"; EMPREINTE_ANNONCEE="$2"; MODE="appliquer"
if [ $# -ge 3 ]; then
  [ "$3" = "--rollback" ] && [ $# -eq 3 ] || paquet_refus "seule option admise : --rollback"
  MODE="rollback"
fi
[[ "$EMPREINTE_ANNONCEE" =~ ^[0-9a-f]{12}$ ]] || paquet_refus "empreinte : 12 caractères hexadécimaux attendus"

RACINE="$(paquet_racine)"

# 1. Garde-fous eux-mêmes commités (ce qui s'exécute est ce qui a été relu).
[ -z "$(git -C "$RACINE" status --porcelain -- scripts .claude CLAUDE.md)" ] \
  || paquet_refus "scripts/, .claude/ ou CLAUDE.md ont des modifications non commitées"

# 2. Paquet conforme, inchangé, validé pour cette empreinte.
paquet_controler "$ID"
[ "${PAQUET_EMPREINTE:0:12}" = "$EMPREINTE_ANNONCEE" ] \
  || paquet_refus "empreinte annoncée $EMPREINTE_ANNONCEE ≠ empreinte du paquet ${PAQUET_EMPREINTE:0:12}"
M="$PAQUET_DIR/manifeste.json"
JOURNAL_DIR="$PAQUET_DIR/journal"

# 3. Pas de double application.
if [ "$MODE" = appliquer ] && [ -d "$JOURNAL_DIR" ] \
   && grep -lqs -e '^RESULTAT: SUCCES$' "$JOURNAL_DIR"/*-appliquer.log 2>/dev/null; then
  paquet_refus "paquet déjà appliqué avec succès (voir journal/) : créer un nouveau paquet"
fi

echo "Paquet $ID : contrôles OK (niveau $PAQUET_NIVEAU, empreinte ${PAQUET_EMPREINTE:0:12}, mode $MODE)"

# 4. Seulement dans la session dédiée « Swend – écriture prod ».
if [ "${SWEND_SESSION_ECRITURE:-}" != "1" ]; then
  echo "ARRÊT : cette session n'est pas « Swend – écriture prod » (SWEND_SESSION_ECRITURE=1 absent)." >&2
  echo "Aucune requête n'a été envoyée." >&2
  exit 3
fi
API_BASE="${SWEND_API_BASE:-https://api.supabase.com}"
if [ "$API_BASE" != "https://api.supabase.com" ]; then
  # Seule exception : un faux serveur local pour les tests de la porte.
  [[ "$API_BASE" =~ ^http://(127\.0\.0\.1|localhost):[0-9]+$ ]] \
    || paquet_refus "SWEND_API_BASE ne peut viser qu'un serveur de test local"
fi
URL_ECRITURE="$API_BASE/v1/projects/$PAQUET_PROJET_ATTENDU/database/query"
URL_LECTURE="$URL_ECRITURE/read-only"

# 5. Exécution journalisée, arrêt à la première erreur.
mkdir -p "$JOURNAL_DIR"
HORODATAGE="$(date -u +%Y%m%dT%H%M%SZ)"
JOURNAL="$JOURNAL_DIR/$HORODATAGE-$MODE.log"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
journal() { printf '%s\n' "$*" >> "$JOURNAL"; }

if [ "$MODE" = appliquer ]; then
  FILTRE='[.sauvegardes[]?, .etapes[]]'
else
  jq -e '(.rollback | type == "array") and (.rollback | length > 0)' "$M" >/dev/null \
    || paquet_refus "ce paquet n'a pas de rollback exécutable (rollback_justification)"
  FILTRE='[.rollback[]]'
fi
NB="$(jq "$FILTRE | length" "$M")"

journal "PAQUET: $ID"
journal "MODE: $MODE"
journal "NIVEAU: $PAQUET_NIVEAU"
journal "EMPREINTE: $PAQUET_EMPREINTE"
journal "VALIDATION: $(jq -c '{go, valide_par, valide_le}' "$PAQUET_DIR/validation.json")"
journal "COMMIT: $(git -C "$RACINE" rev-parse HEAD)"
journal "DEBUT: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
journal "PLAN:"
for ((i = 0; i < NB; i++)); do
  journal "  $((i + 1)). $(jq -r "$FILTRE[$i] | \"\(.nom) — \(.type) — \(.fichier) — sha256 \(.sha256)\"" "$M")"
done

echec() {
  journal "RESULTAT: ECHEC"
  journal "FIN: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ÉCHEC : $* — exécution arrêtée. Journal : ${JOURNAL#"$RACINE"/}" >&2
  exit 1
}

for ((i = 0; i < NB; i++)); do
  NOM="$(jq -r "$FILTRE[$i].nom" "$M")"
  TYPE="$(jq -r "$FILTRE[$i].type" "$M")"
  FICHIER="$(jq -r "$FILTRE[$i].fichier" "$M")"
  case "$TYPE" in
    sql_ecriture) URL="$URL_ECRITURE" ;;
    sql_lecture)  URL="$URL_LECTURE" ;;
    *) echec "type d'étape non pris en charge : $TYPE" ;;
  esac
  # Re-vérification juste avant l'envoi (rien ne doit bouger pendant l'exécution).
  [ "$(sha256sum "$PAQUET_DIR/$FICHIER" | cut -d' ' -f1)" = "$(jq -r "$FILTRE[$i].sha256" "$M")" ] \
    || echec "artefact $FICHIER modifié pendant l'exécution"
  jq -n --rawfile q "$PAQUET_DIR/$FICHIER" '{query: $q}' > "$TMP/corps.json"
  journal "ETAPE $((i + 1)): $NOM ($TYPE, $FICHIER) -> ${URL#"$API_BASE"}"
  CODE="$(curl -sS -o "$TMP/reponse" -w '%{http_code}' -X POST "$URL" \
            -H 'Content-Type: application/json' --data-binary @"$TMP/corps.json")" \
    || { journal "  ERREUR RESEAU"; echec "étape $NOM : erreur réseau"; }
  journal "  HTTP: $CODE"
  journal "  REPONSE: $(head -c 20000 "$TMP/reponse")"
  echo "Étape $((i + 1))/$NB $NOM : HTTP $CODE"
  [[ "$CODE" =~ ^2[0-9][0-9]$ ]] || echec "étape $NOM : HTTP $CODE"
done

journal "RESULTAT: SUCCES"
journal "FIN: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "SUCCÈS : $NB étape(s) exécutée(s). Reçu : ${JOURNAL#"$RACINE"/}"
