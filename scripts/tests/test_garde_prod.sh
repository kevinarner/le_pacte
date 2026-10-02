#!/bin/bash
# Tests des garde-fous de production, sans aucune production :
#  - porte scripts/prod_ecrire.sh et contrôleur, sur des paquets fictifs dans
#    un dépôt git temporaire, avec un faux serveur HTTP local (127.0.0.1) ;
#  - hook .claude/hooks/garde_prod.py, sur les cas de scripts/tests/cas_hook.tsv.
# Usage : scripts/tests/test_garde_prod.sh      (sortie 0 si tout passe)
set -uo pipefail

SOURCE="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
T="$(mktemp -d)"
SERVEUR_PID=""
trap '[ -n "$SERVEUR_PID" ] && kill "$SERVEUR_PID" 2>/dev/null; rm -rf "$T"' EXIT
OK=0; KO=0
reussi() { OK=$((OK + 1)); printf '  ok    %s\n' "$1"; }
rate()   { KO=$((KO + 1)); printf '  ÉCHEC %s\n        %s\n' "$1" "$2"; }

# --- Dépôt temporaire : copie des garde-fous ------------------------------
R="$T/depot"
mkdir -p "$R/supabase/changements"
cp -r "$SOURCE/scripts" "$SOURCE/.claude" "$SOURCE/CLAUDE.md" "$R/"
git -C "$R" init -q
git -C "$R" config user.email test@example.invalid
git -C "$R" config user.name test
git -C "$R" add -A && git -C "$R" commit -qm "garde-fous"
unset SWEND_SESSION_ECRITURE SWEND_API_BASE

sha() { sha256sum "$1" | cut -d' ' -f1; }

# creer_paquet <ID> <niveau> : paquet conforme, commité, non validé.
creer_paquet() {
  local id="$1" niveau="$2" d="$R/supabase/changements/$1"
  mkdir -p "$d"
  printf -- '-- %s\nbegin;\nselect 1;\ncommit;\n' "$id" > "$d/appliquer.sql"
  printf -- 'select 1 as ok;\n' > "$d/verifier.sql"
  printf -- 'begin;\nselect 2;\ncommit;\n' > "$d/rollback.sql"
  printf -- 'begin;\ncreate table if not exists sauvegarde_test as select 1;\ncommit;\n' > "$d/sauvegarde.sql"
  {
    echo "# $id"
    for s in "Objectif" "Fichiers concernés" "Préconditions" "Impact attendu" \
             "Vérifications après exécution" "Rollback" "Sauvegardes"; do
      printf '\n## %s\n\nTexte.\n' "$s"
    done
  } > "$d/paquet.md"
  jq -n --arg id "$id" --argjson n "$niveau" \
    --arg a "$(sha "$d/appliquer.sql")" --arg v "$(sha "$d/verifier.sql")" \
    --arg r "$(sha "$d/rollback.sql")" --arg s "$(sha "$d/sauvegarde.sql")" '{
      id: $id, niveau: $n, projet: "ssciqjpaibdorvnkkhsk", objectif: "Test.",
      sauvegardes: (if $n == 2 then [{nom: "sauvegarde", type: "sql_ecriture", fichier: "sauvegarde.sql", sha256: $s}] else [] end),
      etapes: [{nom: "appliquer", type: "sql_ecriture", fichier: "appliquer.sql", sha256: $a},
               {nom: "verifier",  type: "sql_lecture",  fichier: "verifier.sql",  sha256: $v}],
      rollback: [{nom: "rollback", type: "sql_ecriture", fichier: "rollback.sql", sha256: $r}]
    }' > "$d/manifeste.json"
  [ "$niveau" = 2 ] || rm -f "$d/sauvegarde.sql"
  git -C "$R" add -A && git -C "$R" commit -qm "paquet $id"
}
valider() {  # valider <ID> <Prénom>...
  local id="$1"; shift
  local args=(); for p in "$@"; do args+=(--par "$p"); done
  "$R/scripts/paquet_controler.sh" "$id" --enregistrer-go "Go $id" "${args[@]}" >/dev/null \
    && git -C "$R" add -A && git -C "$R" commit -qm "Go $id"
}
empreinte() { "$R/scripts/paquet_controler.sh" "$1" --avant-go | sed -n 's/^  empreinte  : //p' | cut -c1-12; }

# attendre <libellé> <code attendu> <motif attendu (sortie) ou ""> -- commande...
attendre() {
  local lib="$1" code_attendu="$2" motif="$3"; shift 4
  local sortie code
  sortie="$("$@" 2>&1)"; code=$?
  if [ "$code" != "$code_attendu" ]; then
    rate "$lib" "code $code au lieu de $code_attendu : $(tail -n2 <<<"$sortie" | tr '\n' ' ')"
  elif [ -n "$motif" ] && ! grep -q -- "$motif" <<<"$sortie"; then
    rate "$lib" "motif « $motif » absent : $(tail -n2 <<<"$sortie" | tr '\n' ' ')"
  else
    reussi "$lib"
  fi
}

# --- Faux serveur local ------------------------------------------------------
cat > "$T/serveur.py" <<'PY'
import http.server, json, os, sys
journal, mode = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        corps = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(journal, "a") as f:
            f.write(json.dumps({"chemin": self.path, "corps": corps,
                                "entetes": {k.lower(): v for k, v in self.headers.items()}}) + "\n")
        n = sum(1 for _ in open(journal))
        code = 400 if (mode == "echec" and n == 1) else 201
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(b'[{"ok":1}]' if code == 201 else b'{"message":"erreur simulee"}')
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_port, flush=True)
s.serve_forever()
PY
demarrer_serveur() {  # demarrer_serveur <mode ok|echec>
  [ -n "$SERVEUR_PID" ] && kill "$SERVEUR_PID" 2>/dev/null
  : > "$T/requetes.jsonl"; : > "$T/port"
  python3 "$T/serveur.py" "$T/requetes.jsonl" "$1" > "$T/port" &
  SERVEUR_PID=$!
  for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
  BASE="http://127.0.0.1:$(head -n1 "$T/port")"
}

PORTE="$R/scripts/prod_ecrire.sh"
CTRL="$R/scripts/paquet_controler.sh"

echo "== Porte et contrôleur (paquets fictifs)"

creer_paquet TEST-01 1
attendre "avant Go : contrôle affiche l'empreinte" 0 "empreinte" -- "$CTRL" TEST-01 --avant-go
attendre "paquet non validé → refus" 1 "paquet non validé" -- "$PORTE" TEST-01 000000000000
attendre "Go mal libellé → refus" 1 "exactement" -- "$CTRL" TEST-01 --enregistrer-go "go TEST-01" --par Kevin
attendre "Go par un non-fondateur → refus" 1 "pas un fondateur" -- "$CTRL" TEST-01 --enregistrer-go "Go TEST-01" --par Martin
valider TEST-01 Kevin
E1="$(empreinte TEST-01)"
attendre "Go déjà enregistré → pas de revalidation" 1 "existe déjà" -- "$CTRL" TEST-01 --enregistrer-go "Go TEST-01" --par Kevin
attendre "contrôle complet d'un paquet validé" 0 "contrôles OK" -- "$CTRL" TEST-01
attendre "paquet conforme, hors session d'écriture → arrêt avant envoi" 3 "SWEND_SESSION_ECRITURE=1 absent" -- "$PORTE" TEST-01 "$E1"
[ ! -d "$R/supabase/changements/TEST-01/journal" ] && reussi "hors session d'écriture : aucun journal, aucune requête" \
  || rate "hors session d'écriture : aucun journal" "un journal a été créé"
attendre "mauvaise empreinte annoncée → refus" 1 "empreinte annoncée" -- "$PORTE" TEST-01 0123456789ab
attendre "empreinte mal formée → refus" 1 "12 caractères" -- "$PORTE" TEST-01 xyz
attendre "option inconnue → refus" 1 "seule option" -- "$PORTE" TEST-01 "$E1" --force
attendre "API hors serveur local → refus" 1 "serveur de test local" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE=https://exemple.invalid "$PORTE" TEST-01 "$E1"

demarrer_serveur ok
attendre "paquet conforme en session d'écriture (faux serveur) → exécuté" 0 "SUCCÈS : 2 étape" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-01 "$E1"
if [ "$(jq -r .chemin "$T/requetes.jsonl" | tr '\n' ' ')" = "/v1/projects/ssciqjpaibdorvnkkhsk/database/query /v1/projects/ssciqjpaibdorvnkkhsk/database/query/read-only " ]; then
  reussi "écriture sur …/database/query puis vérification sur …/read-only, dans l'ordre"
else rate "chemins des requêtes" "$(jq -r .chemin "$T/requetes.jsonl" | tr '\n' ' ')"; fi
[ "$(head -n1 "$T/requetes.jsonl" | jq -r '.corps | fromjson | .query')" = "$(cat "$R/supabase/changements/TEST-01/appliquer.sql")" ] \
  && reussi "SQL envoyé = artefact validé, octet pour octet" || rate "SQL envoyé" "différent de appliquer.sql"
J="$(ls "$R"/supabase/changements/TEST-01/journal/*-appliquer.log)"
grep -q '^RESULTAT: SUCCES$' "$J" && grep -q "^EMPREINTE: " "$J" && grep -q '^PLAN:' "$J" && grep -q '^COMMIT: ' "$J" \
  && reussi "reçu : plan, empreinte, commit, résultat" || rate "reçu" "champs manquants"
if grep -qi -e authorization -e bearer -e apikey "$J" || jq -e 'select(.entetes.authorization or .entetes.apikey)' "$T/requetes.jsonl" >/dev/null; then
  rate "aucun identifiant envoyé ni journalisé" "un en-tête d'authentification est présent"
else reussi "aucun identifiant envoyé ni journalisé par la porte"; fi
attendre "double application → refus" 1 "déjà appliqué" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-01 "$E1"
: > "$T/requetes.jsonl"
attendre "rollback validé → exécuté" 0 "SUCCÈS : 1 étape" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-01 "$E1" --rollback
[ "$(head -n1 "$T/requetes.jsonl" | jq -r '.corps | fromjson | .query')" = "$(cat "$R/supabase/changements/TEST-01/rollback.sql")" ] \
  && reussi "rollback : envoie exactement rollback.sql" || rate "rollback" "SQL différent"

creer_paquet TEST-02 1; valider TEST-02 Kevin; E2="$(empreinte TEST-02)"
demarrer_serveur echec
attendre "erreur HTTP à la 1re étape → arrêt immédiat" 1 "HTTP 400" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-02 "$E2"
[ "$(wc -l < "$T/requetes.jsonl")" = 1 ] && reussi "après l'erreur : aucune étape suivante envoyée" \
  || rate "arrêt immédiat" "$(wc -l < "$T/requetes.jsonl") requêtes envoyées"
grep -q '^RESULTAT: ECHEC$' "$R"/supabase/changements/TEST-02/journal/*-appliquer.log \
  && reussi "reçu d'échec journalisé" || rate "reçu d'échec" "absent"

creer_paquet TEST-03 1; valider TEST-03 Kevin; E3="$(empreinte TEST-03)"
echo "-- ajout" >> "$R/supabase/changements/TEST-03/appliquer.sql"
attendre "artefact modifié, non commité → refus" 1 "modifié" -- "$PORTE" TEST-03 "$E3"
git -C "$R" commit -qam "modif TEST-03"
attendre "artefact modifié et commité → refus (SHA-256)" 1 "modifié" -- "$PORTE" TEST-03 "$E3"
D3="$R/supabase/changements/TEST-03"
jq --arg s "$(sha "$D3/appliquer.sql")" '.etapes[0].sha256 = $s' "$D3/manifeste.json" > "$T/m" && mv "$T/m" "$D3/manifeste.json"
git -C "$R" commit -qam "manifeste TEST-03 réaligné"
attendre "SHA réalignés après le Go → refus (empreinte ≠ Go)" 1 "a changé depuis le Go" -- "$PORTE" TEST-03 "$E3"

creer_paquet TEST-04 1; valider TEST-04 Kevin; E4="$(empreinte TEST-04)"
jq '.go = "Go TEST-99"' "$R/supabase/changements/TEST-04/validation.json" > "$T/v" && mv "$T/v" "$R/supabase/changements/TEST-04/validation.json"
git -C "$R" commit -qam "Go falsifié"
attendre "validation.json falsifiée → refus" 1 "Go doit être exactement" -- "$PORTE" TEST-04 "$E4"

casser() {  # casser <ID> <libellé> <motif> <commande jq ou shell sur le dossier>
  local id="$1" lib="$2" motif="$3" action="$4" d="$R/supabase/changements/$1"
  creer_paquet "$id" 1
  ( cd "$d" && eval "$action" )
  git -C "$R" add -A && git -C "$R" commit -qm "casse $id"
  attendre "$lib" 1 "$motif" -- "$CTRL" "$id" --avant-go
}
casser TEST-05 "manifeste JSON invalide → refus" "pas un objet JSON" 'echo "{" > manifeste.json'
casser TEST-06 "niveau 3 → refus" "niveau doit être 1 ou 2" 'jq ".niveau = 3" manifeste.json > m && mv m manifeste.json'
casser TEST-07 "objectif manquant → refus" "objectif manquant" 'jq "del(.objectif)" manifeste.json > m && mv m manifeste.json'
casser TEST-08 "section absente de paquet.md → refus" "Rollback" 'sed -i "/^## Rollback$/d" paquet.md'
casser TEST-09 "chemin dans un nom d'artefact → refus" "nom de fichier interdit" 'jq ".etapes[0].fichier = \"../x.sql\"" manifeste.json > m && mv m manifeste.json'
casser TEST-10 "fichier inattendu dans le paquet → refus" "fichier inattendu" 'echo x > notes.txt'
casser TEST-11 "écriture sans transaction → refus" "begin;" 'printf "select 1;\n" > appliquer.sql && jq --arg s "$(sha256sum appliquer.sql | cut -d" " -f1)" ".etapes[0].sha256 = \$s" manifeste.json > m && mv m manifeste.json'
casser TEST-12 "type edge_function → refus explicite" "pas encore pris en charge" 'jq ".etapes[0].type = \"edge_function\"" manifeste.json > m && mv m manifeste.json'
casser TEST-13 "projet inattendu → refus" "projet inattendu" 'jq ".projet = \"autreprojet\"" manifeste.json > m && mv m manifeste.json'
casser TEST-14 "sha256 absent → refus" "sha256 manquant" 'jq "del(.etapes[0].sha256)" manifeste.json > m && mv m manifeste.json'

creer_paquet TEST-20 2
valider TEST-20 Kevin; E20="$(empreinte TEST-20)"
attendre "niveau 2 avec un seul fondateur → refus" 1 "deux fondateurs" -- "$PORTE" TEST-20 "$E20"
creer_paquet TEST-21 2; valider TEST-21 Kevin Eliot
attendre "niveau 2 avec les deux fondateurs → contrôle OK" 0 "contrôles OK" -- "$CTRL" TEST-21
creer_paquet TEST-22 2
jq 'del(.sauvegardes)' "$R/supabase/changements/TEST-22/manifeste.json" > "$T/m" && mv "$T/m" "$R/supabase/changements/TEST-22/manifeste.json"
rm "$R/supabase/changements/TEST-22/sauvegarde.sql"; git -C "$R" add -A; git -C "$R" commit -qm x
attendre "niveau 2 sans sauvegarde → refus" 1 "sauvegardes" -- "$CTRL" TEST-22 --avant-go

mkdir -p "$R/supabase/changements/TEST-30"; cp "$R"/supabase/changements/TEST-01/{paquet.md,manifeste.json,appliquer.sql,verifier.sql,rollback.sql} "$R/supabase/changements/TEST-30/"
attendre "paquet non commité → refus" 1 "" -- "$CTRL" TEST-30 --avant-go
rm -rf "$R/supabase/changements/TEST-30"
attendre "identifiant invalide (_modele) → refus" 1 "identifiant invalide" -- "$CTRL" _modele --avant-go
attendre "paquet inexistant → refus" 1 "introuvable" -- "$CTRL" TEST-99 --avant-go

echo "# modif" >> "$R/scripts/prod_ecrire.sh"
attendre "porte modifiée non commitée → refus" 1 "modifications non commitées" -- "$PORTE" TEST-21 "$(empreinte TEST-21)"
git -C "$R" checkout -q -- scripts/prod_ecrire.sh
echo '{}' > "$R/.claude/settings.local.json"
attendre ".claude/ modifié → refus" 1 "modifications non commitées" -- "$PORTE" TEST-21 "$(empreinte TEST-21)"
rm "$R/.claude/settings.local.json"

echo
echo "== Hook PreToolUse (cas de scripts/tests/cas_hook.tsv)"
HOOK="$R/.claude/hooks/garde_prod.py"
mkdir -p "$T/h"
# L'URL d'écriture est assemblée ici pour que ce script de test ne soit pas
# lui-même bloqué par le hook ; elle n'est jamais appelée (cas analysés seulement).
HOTE_API="api.supa"; HOTE_API="${HOTE_API}base.com"
URL_W="https://$HOTE_API/v1/projects/ssciqjpaibdorvnkkhsk/database/query"
printf '#!/bin/bash\ncurl -sS -X POST "%s" -d @q.json\n' "$URL_W" > "$T/h/ecriture.sh"
printf '#!/bin/bash\ncurl -sS -X POST "%s/read-only" -d @q.json\n' "$URL_W" > "$T/h/lecture.sh"
printf 'import urllib.request\nurllib.request.urlopen("%s", data=b"{}")\n' "$URL_W" > "$T/h/ecriture.py"
printf '#!/bin/bash\nscripts/prod_ecrire.sh R1b-01 0123456789ab\n' > "$T/h/enveloppe.sh"
printf '#!/bin/bash\nscripts/prod_ecrire.sh R1b-01 0123456789ab\n' > "$R/scripts/enveloppe_test.sh"
chmod +x "$T"/h/*.sh
while IFS=$'\t' read -r attendu commande; do
  case "$attendu" in ''|\#*) continue ;; esac
  commande="${commande//\{ECRITURE_SH\}/$T/h/ecriture.sh}"
  commande="${commande//\{LECTURE_SH\}/$T/h/lecture.sh}"
  commande="${commande//\{ECRITURE_PY\}/$T/h/ecriture.py}"
  commande="${commande//\{WRAPPER_HORS_SCRIPTS\}/$T/h/enveloppe.sh}"
  commande="${commande//\{WRAPPER_SCRIPTS\}/scripts/enveloppe_test.sh}"
  jq -n --arg c "$commande" --arg d "$R" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' \
    | python3 "$HOOK" >/dev/null 2>"$T/h/err"
  code=$?
  case "$attendu" in
    BLOQUE)   [ "$code" = 2 ] && reussi "bloqué   : ${commande:0:90}" || rate "devait être bloqué : $commande" "code $code" ;;
    AUTORISE) [ "$code" = 0 ] && reussi "autorisé : ${commande:0:90}" || rate "devait passer : $commande" "code $code : $(cat "$T/h/err")" ;;
    LIMITE)   [ "$code" = 0 ] && reussi "limite connue (non couverte) : ${commande:0:70}" \
                || rate "limite annoncée qui a changé (désormais bloquée) : $commande" "mettre à jour la documentation" ;;
    *) rate "attendu inconnu : $attendu" "" ;;
  esac
done < "$SOURCE/scripts/tests/cas_hook.tsv"
echo '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | python3 "$HOOK" && reussi "autres outils que Bash : ignorés" || rate "autres outils" "bloqués"

echo
echo "Résultat : $OK réussis, $KO échoués"
[ "$KO" = 0 ]
