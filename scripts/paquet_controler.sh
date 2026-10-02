#!/bin/bash
# Contrôle local d'un change packet de production — aucun accès réseau.
#
#   scripts/paquet_controler.sh <ID> --avant-go
#       contrôle le paquet (format, artefacts, SHA-256, commit) et affiche son
#       empreinte : à présenter avec le paquet pour obtenir « Go <ID> ».
#   scripts/paquet_controler.sh <ID> --enregistrer-go "Go <ID>" --par <Prénom> [--par <Prénom>]
#       après le Go écrit par un fondateur dans la conversation : crée
#       validation.json pour l'empreinte actuelle (à committer ensuite).
#   scripts/paquet_controler.sh <ID>
#       contrôle complet, validation comprise (ce que vérifie la porte).
#
# Format : supabase/changements/README.md.
set -euo pipefail
. "$(dirname "$0")/lib/paquet.sh"

[ $# -ge 1 ] || paquet_refus "usage : scripts/paquet_controler.sh <ID> [--avant-go | --enregistrer-go \"Go <ID>\" --par <Prénom>...]"
ID="$1"; shift
MODE="complet"; GO=""; PAR=()
while [ $# -gt 0 ]; do
  case "$1" in
    --avant-go) MODE="avant-go"; shift ;;
    --enregistrer-go) MODE="enregistrer-go"; GO="${2:-}"; shift 2 || paquet_refus "texte du Go manquant" ;;
    --par) PAR+=("${2:-}"); shift 2 || paquet_refus "prénom manquant après --par" ;;
    *) paquet_refus "option inconnue : $1" ;;
  esac
done

case "$MODE" in
  avant-go)
    paquet_controler "$ID" --sans-validation
    ;;
  enregistrer-go)
    paquet_controler "$ID" --sans-validation
    [ "$GO" = "Go $ID" ] || paquet_refus "le texte du Go doit être exactement « Go $ID »"
    [ "${#PAR[@]}" -ge 1 ] || paquet_refus "--par <Prénom> obligatoire"
    for p in "${PAR[@]}"; do
      printf '%s\n' "${PAQUET_FONDATEURS[@]}" | grep -qx "$p" \
        || paquet_refus "« $p » n'est pas un fondateur (${PAQUET_FONDATEURS[*]})"
    done
    [ ! -e "$PAQUET_DIR/validation.json" ] \
      || paquet_refus "validation.json existe déjà : un paquet validé ne se revalide pas, créer un nouvel identifiant"
    jq -n --arg id "$ID" --arg go "$GO" --arg e "$PAQUET_EMPREINTE" \
      --arg le "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --args \
      '{id: $id, go: $go, empreinte_paquet: $e, valide_par: $ARGS.positional, valide_le: $le}' \
      "${PAR[@]}" > "$PAQUET_DIR/validation.json"
    echo "validation.json écrit pour « $GO » ($(IFS=,; echo "${PAR[*]}")) — à committer."
    ;;
  complet)
    paquet_controler "$ID"
    ;;
esac

echo "Paquet $ID : contrôles OK (mode $MODE)"
echo "  niveau     : $PAQUET_NIVEAU"
echo "  empreinte  : $PAQUET_EMPREINTE"
echo "  à approuver: scripts/prod_ecrire.sh $ID ${PAQUET_EMPREINTE:0:12}"
