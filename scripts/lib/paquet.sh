#!/bin/bash
# Contrôles communs des change packets de production (supabase/changements/).
# À « sourcer » par scripts/paquet_controler.sh et scripts/prod_ecrire.sh.
# Format et cycle de vie : supabase/changements/README.md.
#
# Aucune fonction ici ne contacte le réseau.

PAQUET_PROJET_ATTENDU="ssciqjpaibdorvnkkhsk"
PAQUET_FONDATEURS=("Kevin" "Eliot")
PAQUET_SECTIONS=(
  "## Objectif"
  "## Fichiers concernés"
  "## Préconditions"
  "## Impact attendu"
  "## Vérifications après exécution"
  "## Rollback"
  "## Sauvegardes"
)

paquet_racine() { git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel; }

paquet_refus() { echo "REFUS : $*" >&2; exit 1; }

# Étape « edge_function » : fonction existante du dépôt, d'un seul fichier
# (index.ts, sans import_map ni fichier statique), verify_jwt explicite.
paquet_controler_fonction() {
  local racine="$1" etape="$2" fonction fichiers
  jq -e '.fonction | type == "string"' <<<"$etape" >/dev/null \
    || paquet_refus "Edge Function : champ « fonction » manquant"
  fonction="$(jq -r '.fonction' <<<"$etape")"
  [[ "$fonction" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] \
    || paquet_refus "Edge Function : nom invalide « $fonction »"
  fichiers="$(git -C "$racine" ls-files -- "supabase/functions/$fonction/")"
  [ -n "$fichiers" ] \
    || paquet_refus "Edge Function « $fonction » inconnue : aucun supabase/functions/$fonction/ versionné"
  [ "$fichiers" = "supabase/functions/$fonction/index.ts" ] \
    || paquet_refus "Edge Function « $fonction » : seules les fonctions d'un seul fichier index.ts sont prises en charge"
  jq -e '.verify_jwt | type == "boolean"' <<<"$etape" >/dev/null \
    || paquet_refus "Edge Function « $fonction » : verify_jwt (true/false) obligatoire"
}

# Fichiers du paquet couverts par l'empreinte (triés, sans validation.json ni journal/).
paquet_fichiers() {
  local dir="$1"
  {
    echo "manifeste.json"
    echo "paquet.md"
    jq -r '[.sauvegardes[]?, .etapes[]?, .rollback[]?] | .[].fichier' "$dir/manifeste.json"
  } | sort -u
}

# Empreinte du paquet : sha256 de la liste « sha256  fichier » de tous ses fichiers.
paquet_empreinte() {
  local dir="$1" f
  paquet_fichiers "$dir" | while read -r f; do
    printf '%s  %s\n' "$(sha256sum "$dir/$f" | cut -d' ' -f1)" "$f"
  done | sha256sum | cut -d' ' -f1
}

# Contrôle complet d'un paquet : format, artefacts, SHA-256, git, validation.
# Usage : paquet_controler <ID> [--sans-validation]
# En sortie : variables PAQUET_DIR, PAQUET_EMPREINTE, PAQUET_NIVEAU.
paquet_controler() {
  local id="$1" sans_validation="${2:-}"
  local racine; racine="$(paquet_racine)" || paquet_refus "pas dans un dépôt git"

  [[ "$id" =~ ^[A-Za-z0-9]+(-[A-Za-z0-9]+)*-[0-9]{2}$ ]] \
    || paquet_refus "identifiant invalide « $id » (format attendu : R1b-01)"
  PAQUET_DIR="$racine/supabase/changements/$id"
  [ -d "$PAQUET_DIR" ] || paquet_refus "paquet introuvable : supabase/changements/$id"
  local m="$PAQUET_DIR/manifeste.json"
  [ -f "$m" ] || paquet_refus "manifeste.json absent"
  [ -f "$PAQUET_DIR/paquet.md" ] || paquet_refus "paquet.md absent"
  jq -e 'type == "object"' "$m" >/dev/null 2>&1 || paquet_refus "manifeste.json n'est pas un objet JSON valide"

  # Champs obligatoires.
  [ "$(jq -r '.id' "$m")" = "$id" ] || paquet_refus "manifeste : id différent du dossier"
  PAQUET_NIVEAU="$(jq -r '.niveau' "$m")"
  [[ "$PAQUET_NIVEAU" =~ ^[12]$ ]] \
    || paquet_refus "manifeste : niveau doit être 1 ou 2 (le niveau 3 n'est jamais exécutable)"
  [ "$(jq -r '.projet' "$m")" = "$PAQUET_PROJET_ATTENDU" ] || paquet_refus "manifeste : projet inattendu"
  jq -e '(.objectif | type == "string") and (.objectif | length > 0)' "$m" >/dev/null \
    || paquet_refus "manifeste : objectif manquant"
  jq -e '(.etapes | type == "array") and (.etapes | length > 0)' "$m" >/dev/null \
    || paquet_refus "manifeste : etapes manquantes"
  jq -e '((.rollback | type == "array") and (.rollback | length > 0)) or ((.rollback_justification | type == "string") and (.rollback_justification | length > 0))' "$m" >/dev/null \
    || paquet_refus "manifeste : rollback (ou rollback_justification) manquant"
  if [ "$PAQUET_NIVEAU" = 2 ]; then
    jq -e '((.sauvegardes | type == "array") and (.sauvegardes | length > 0)) or ((.sauvegarde_justification | type == "string") and (.sauvegarde_justification | length > 0))' "$m" >/dev/null \
      || paquet_refus "niveau 2 : sauvegardes (ou sauvegarde_justification) obligatoires"
  fi

  # Sections obligatoires de paquet.md.
  head -n1 "$PAQUET_DIR/paquet.md" | grep -qx "# $id" || paquet_refus "paquet.md doit commencer par « # $id »"
  local s
  for s in "${PAQUET_SECTIONS[@]}"; do
    grep -qx "$s" "$PAQUET_DIR/paquet.md" || paquet_refus "paquet.md : section « $s » absente"
  done

  # Étapes : type connu, fichier dans le paquet, SHA-256 conforme.
  local n i etape type fichier sha attendu transaction
  n="$(jq '[.sauvegardes[]?, .etapes[]?, .rollback[]?] | length' "$m")"
  for ((i = 0; i < n; i++)); do
    etape="$(jq -c "[.sauvegardes[]?, .etapes[]?, .rollback[]?][$i]" "$m")"
    type="$(jq -r '.type' <<<"$etape")"
    fichier="$(jq -r '.fichier' <<<"$etape")"
    attendu="$(jq -r '.sha256' <<<"$etape")"
    transaction="$(jq -r 'if .transaction == false then "non" else "oui" end' <<<"$etape")"
    jq -e '(.nom | type == "string") and (.nom | length > 0)' <<<"$etape" >/dev/null \
      || paquet_refus "étape sans nom"
    case "$type" in
      sql_ecriture|sql_lecture) ;;
      edge_function) paquet_controler_fonction "$racine" "$etape" ;;
      *) paquet_refus "étape « $fichier » : type inconnu « $type »" ;;
    esac
    [[ "$fichier" =~ ^[A-Za-z0-9_.-]+$ && "$fichier" != .* ]] \
      || paquet_refus "étape : nom de fichier interdit « $fichier » (pas de chemin)"
    [ -f "$PAQUET_DIR/$fichier" ] || paquet_refus "artefact absent : $fichier"
    [[ "$attendu" =~ ^[0-9a-f]{64}$ ]] || paquet_refus "artefact $fichier : sha256 manquant ou invalide"
    sha="$(sha256sum "$PAQUET_DIR/$fichier" | cut -d' ' -f1)"
    [ "$sha" = "$attendu" ] || paquet_refus "artefact $fichier modifié : sha256 $sha ≠ attendu $attendu"
    if [ "$type" = sql_ecriture ] && [ "$transaction" = oui ]; then
      # Atomicité : une écriture commence par begin; et finit par commit;
      # (commentaires « -- » et lignes vides ignorés).
      local corps
      corps="$(grep -v '^[[:space:]]*--' "$PAQUET_DIR/$fichier" | grep -v '^[[:space:]]*$' | tr '[:upper:]' '[:lower:]')"
      [ "$(head -n1 <<<"$corps" | tr -d '[:space:]')" = "begin;" ] \
        || paquet_refus "écriture $fichier : doit commencer par « begin; » (ou \"transaction\": false justifié)"
      [ "$(tail -n1 <<<"$corps" | tr -d '[:space:]')" = "commit;" ] \
        || paquet_refus "écriture $fichier : doit finir par « commit; »"
    fi
  done

  # Une Edge Function appliquée (étapes, pas le rollback) doit être exactement
  # la source versionnée du dépôt : ce qui est déployé est ce qui est relu.
  local fonction source
  while read -r etape; do
    fonction="$(jq -r '.fonction' <<<"$etape")"
    fichier="$(jq -r '.fichier' <<<"$etape")"
    source="supabase/functions/$fonction/index.ts"
    [ -z "$(git -C "$racine" status --porcelain -- "$source")" ] \
      || paquet_refus "$source a des modifications non commitées"
    [ "$(sha256sum "$racine/$source" | cut -d' ' -f1)" = "$(sha256sum "$PAQUET_DIR/$fichier" | cut -d' ' -f1)" ] \
      || paquet_refus "Edge Function « $fonction » : l'artefact $fichier ne correspond pas à la source versionnée $source"
  done < <(jq -c '.etapes[] | select(.type == "edge_function")' "$m")

  # Aucun fichier inattendu dans le paquet.
  local present
  while read -r present; do
    case "$present" in
      validation.json) ;;
      *) paquet_fichiers "$PAQUET_DIR" | grep -qx "$present" \
           || paquet_refus "fichier inattendu dans le paquet : $present" ;;
    esac
  done < <(find "$PAQUET_DIR" -mindepth 1 -maxdepth 1 -not -name journal -exec basename {} \;)

  # Versionné et immuable : tout est suivi par git et sans modification locale.
  local rel="supabase/changements/$id"
  local f
  while read -r f; do
    git -C "$racine" ls-files --error-unmatch "$rel/$f" >/dev/null 2>&1 \
      || paquet_refus "$rel/$f n'est pas versionné (commit obligatoire)"
  done < <(paquet_fichiers "$PAQUET_DIR")
  [ -z "$(git -C "$racine" status --porcelain -- "$rel" ":(exclude)$rel/journal")" ] \
    || paquet_refus "le paquet a des modifications non commitées"

  PAQUET_EMPREINTE="$(paquet_empreinte "$PAQUET_DIR")"

  [ "$sans_validation" = "--sans-validation" ] && return 0

  # Validation (Go) : enregistrée, versionnée, et pour CETTE empreinte.
  local v="$PAQUET_DIR/validation.json"
  [ -f "$v" ] || paquet_refus "paquet non validé : validation.json absent (aucun « Go $id » enregistré)"
  git -C "$racine" ls-files --error-unmatch "$rel/validation.json" >/dev/null 2>&1 \
    || paquet_refus "validation.json n'est pas versionné"
  jq -e 'type == "object"' "$v" >/dev/null 2>&1 || paquet_refus "validation.json invalide"
  [ "$(jq -r '.id' "$v")" = "$id" ] || paquet_refus "validation.json : id différent"
  [ "$(jq -r '.go' "$v")" = "Go $id" ] || paquet_refus "validation.json : le texte du Go doit être exactement « Go $id »"
  [ "$(jq -r '.empreinte_paquet' "$v")" = "$PAQUET_EMPREINTE" ] \
    || paquet_refus "le paquet a changé depuis le Go : empreinte actuelle $PAQUET_EMPREINTE ≠ empreinte validée $(jq -r '.empreinte_paquet' "$v")"
  paquet_controler_approbateurs "$(jq -c '.valide_par' "$v")"
  return 0
}

# Même autorité pour l'enregistrement du Go et la lecture d'une validation.
# Les noms sont déclaratifs : ne renseigner que les approbations réelles.
paquet_controler_approbateurs() {
  local approbateurs="$1"
  jq -e 'type == "array" and length > 0 and
    all(.[]; . == "Eliot" or . == "Kevin") and
    (length == (unique | length))' <<<"$approbateurs" >/dev/null \
    || paquet_refus "validation : approbateurs invalides ou dupliqués (Eliot, Kevin)"
  jq -e 'index("Eliot") != null' <<<"$approbateurs" >/dev/null \
    || paquet_refus "validation : Go d'Eliot obligatoire pour les niveaux 1 et 2"
}

# Plan d'exécution lisible, une ligne par étape : « N. nom — type [fonction] —
# fichier — sha256 … ». <filtre> = étapes à exécuter (jq), comme dans la porte.
# Le programme jq est entre apostrophes : ses guillemets internes ne doivent
# jamais passer par le shell (cause des lignes PLAN vides du reçu R1b-01).
paquet_plan() {  # paquet_plan <manifeste.json> <filtre jq>
  jq -r "$2"' | to_entries[]
    | "  \(.key + 1). \(.value.nom) — \(.value.type)\(if .value.fonction then " " + .value.fonction else "" end) — \(.value.fichier) — sha256 \(.value.sha256)"' "$1"
}
