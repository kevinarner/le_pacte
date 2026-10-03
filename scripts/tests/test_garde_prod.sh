#!/bin/bash
# Tests des garde-fous de production, sans aucune production :
#  - porte scripts/prod_ecrire.sh et contrôleur, sur des paquets fictifs dans
#    un dépôt git temporaire, avec un faux serveur HTTP local (127.0.0.1) ;
#  - hook .claude/hooks/garde_prod.py, sur les cas de scripts/tests/cas_hook.tsv.
# Usage : scripts/tests/test_garde_prod.sh [--validation-only]
# --validation-only : contrôles locaux des niveaux 1/2, sans serveur ni réseau.
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
cp -r "$SOURCE/scripts" "$SOURCE/.claude" "$SOURCE/CLAUDE.md" "$SOURCE/.gitignore" "$R/"
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

# Mode ciblé utilisable dans un sandbox interdisant les serveurs localhost.
if [ "${1:-}" = --validation-only ]; then
  CTRL="$R/scripts/paquet_controler.sh"
  PORTE="$R/scripts/prod_ecrire.sh"
  for niveau in 1 2; do
    id="CIBLE-$niveau-01"
    creer_paquet "$id" "$niveau"
    attendre "niveau $niveau : sans validation → refus" 1 "paquet non validé" -- "$CTRL" "$id"
    attendre "niveau $niveau : Kevin seul → refus" 1 "Go d'Eliot obligatoire" -- "$CTRL" "$id" --enregistrer-go "Go $id" --par Kevin
    [ ! -e "$R/supabase/changements/$id/validation.json" ] && reussi "niveau $niveau : refus sans création de validation" || rate "validation" "créée après refus"
    valider "$id" Eliot
    attendre "niveau $niveau : Eliot seul → OK" 0 "contrôles OK" -- "$CTRL" "$id"
    jq -e '.valide_par == ["Eliot"]' "$R/supabase/changements/$id/validation.json" >/dev/null && reussi "niveau $niveau : aucun approbateur ajouté" || rate "approbateurs" "inattendus"
    attendre "niveau $niveau : hors session → aucun envoi" 3 "absent" -- "$PORTE" "$id" "$(empreinte "$id")"
    # Une validation commitée sans Eliot doit aussi être refusée à la lecture.
    d="$R/supabase/changements/$id"
    jq '.valide_par = ["Kevin"]' "$d/validation.json" > "$T/v" && mv "$T/v" "$d/validation.json"
    git -C "$R" commit -qam "validation sans Eliot"
    attendre "niveau $niveau : validation sans Eliot → refus" 1 "Go d'Eliot obligatoire" -- "$CTRL" "$id"
  done
  creer_paquet CIBLE-02-02 2; valider CIBLE-02-02 Kevin Eliot
  attendre "Kevin et Eliot : approbations explicites acceptées" 0 "contrôles OK" -- "$CTRL" CIBLE-02-02
  creer_paquet CIBLE-02-03 2
  attendre "approbateur dupliqué → refus" 1 "dupliqués" -- "$CTRL" CIBLE-02-03 --enregistrer-go "Go CIBLE-02-03" --par Eliot --par Eliot
  for cas in sauvegardes rollback preconditions verifications niveau3; do
    case "$cas" in
      sauvegardes) id=CIBLE-02-04; motif=sauvegardes ;;
      rollback) id=CIBLE-02-05; motif=rollback ;;
      preconditions) id=CIBLE-02-06; motif=Préconditions ;;
      verifications) id=CIBLE-02-07; motif=Vérifications ;;
      niveau3) id=CIBLE-02-08; motif="niveau doit être 1 ou 2" ;;
    esac
    creer_paquet "$id" 2
    python3 - "$R/supabase/changements/$id" "$cas" <<'PYTEST'
import json, pathlib, sys
p, cas = pathlib.Path(sys.argv[1]), sys.argv[2]
if cas in ("sauvegardes", "rollback", "niveau3"):
    m = p / "manifeste.json"
    data = json.loads(m.read_text())
    if cas == "niveau3": data["niveau"] = 3
    else: data.pop(cas)
    m.write_text(json.dumps(data))
else:
    m = p / "paquet.md"
    section = "Préconditions" if cas == "preconditions" else "Vérifications après exécution"
    m.write_text(m.read_text().replace("## " + section + "\n", ""))
PYTEST
    git -C "$R" commit -qam "garde-fou $cas"
    attendre "niveau 2 : garde-fou $cas → refus" 1 "$motif" -- "$CTRL" "$id" --avant-go
  done
  echo "Résultat ciblé : $OK réussis, $KO échoués (aucun serveur, aucun réseau)"
  [ "$KO" = 0 ]; exit $?
fi

# --- Faux serveur local ------------------------------------------------------
cat > "$T/serveur.py" <<'PY'
import http.server, json, os, sys
journal, mode = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def noter(self, corps):
        with open(journal, "a") as f:
            f.write(json.dumps({"methode": self.command, "chemin": self.path, "corps": corps,
                                "entetes": {k.lower(): v for k, v in self.headers.items()}}) + "\n")
        return sum(1 for _ in open(journal))
    def repondre(self, code, corps):
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(json.dumps(corps).encode())
    def do_POST(self):
        corps = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
        n = self.noter(corps)
        if mode == "echec" and n == 1:
            return self.repondre(400, {"message": "erreur simulee"})
        if "/functions/deploy" in self.path:
            return self.repondre(201, {"id": "f1", "slug": self.path.split("slug=")[-1], "status": "ACTIVE", "version": 7})
        self.repondre(201, [{"ok": 1}])
    def do_GET(self):
        self.noter("")
        slug = self.path.rstrip("/").split("/")[-1]
        self.repondre(200, {"id": "f1", "slug": slug, "name": slug, "status": "ACTIVE", "version": 7,
                            "verify_jwt": mode != "jwt_faux", "ezbr_sha256": "e" * 64})
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
attendre "Go mal libellé → refus" 1 "exactement" -- "$CTRL" TEST-01 --enregistrer-go "go TEST-01" --par Eliot
attendre "Go par un non-fondateur → refus" 1 "pas un fondateur" -- "$CTRL" TEST-01 --enregistrer-go "Go TEST-01" --par Martin
valider TEST-01 Eliot
E1="$(empreinte TEST-01)"
attendre "Go déjà enregistré → pas de revalidation" 1 "existe déjà" -- "$CTRL" TEST-01 --enregistrer-go "Go TEST-01" --par Eliot
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
# Non-régression R1b-01 : lignes PLAN vides (programme jq coupé par le shell).
M1="$R/supabase/changements/TEST-01/manifeste.json"
PLAN_ATTENDU="$(printf '  1. appliquer — sql_ecriture — appliquer.sql — sha256 %s\n  2. verifier — sql_lecture — verifier.sql — sha256 %s' \
  "$(jq -r '.etapes[0].sha256' "$M1")" "$(jq -r '.etapes[1].sha256' "$M1")")"
[ "$(sed -n '/^PLAN:$/,/^ETAPE /p' "$J" | sed '1d;$d')" = "$PLAN_ATTENDU" ] \
  && reussi "reçu : PLAN contient chaque étape du manifeste (nom, type, fichier, sha256)" \
  || rate "reçu : PLAN" "$(sed -n '/^PLAN:$/,/^ETAPE /p' "$J" | tr '\n' '|')"
if ! git -C "$R" check-ignore -q "$J" && [ "$(git -C "$R" status --porcelain -- "$J")" = "?? ${J#"$R"/}" ]; then
  reussi "reçu journal/*.log : non ignoré, ajoutable sans git add -f"
else rate "reçu journal/*.log" "ignoré par .gitignore"; fi
git -C "$R" add "$J" && git -C "$R" commit -qm "reçu TEST-01" \
  && reussi "reçu : git add normal puis commit" || rate "reçu : git add" "refusé"
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
grep -qx "  1. rollback — sql_ecriture — rollback.sql — sha256 $(jq -r '.rollback[0].sha256' "$M1")" \
  "$R"/supabase/changements/TEST-01/journal/*-rollback.log \
  && reussi "reçu de rollback : PLAN contient l'étape de rollback" || rate "PLAN du rollback" "ligne absente"

creer_paquet TEST-02 1; valider TEST-02 Eliot; E2="$(empreinte TEST-02)"
demarrer_serveur echec
attendre "erreur HTTP à la 1re étape → arrêt immédiat" 1 "HTTP 400" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-02 "$E2"
[ "$(wc -l < "$T/requetes.jsonl")" = 1 ] && reussi "après l'erreur : aucune étape suivante envoyée" \
  || rate "arrêt immédiat" "$(wc -l < "$T/requetes.jsonl") requêtes envoyées"
grep -q '^RESULTAT: ECHEC$' "$R"/supabase/changements/TEST-02/journal/*-appliquer.log \
  && reussi "reçu d'échec journalisé" || rate "reçu d'échec" "absent"

creer_paquet TEST-03 1; valider TEST-03 Eliot; E3="$(empreinte TEST-03)"
echo "-- ajout" >> "$R/supabase/changements/TEST-03/appliquer.sql"
attendre "artefact modifié, non commité → refus" 1 "modifié" -- "$PORTE" TEST-03 "$E3"
git -C "$R" commit -qam "modif TEST-03"
attendre "artefact modifié et commité → refus (SHA-256)" 1 "modifié" -- "$PORTE" TEST-03 "$E3"
D3="$R/supabase/changements/TEST-03"
jq --arg s "$(sha "$D3/appliquer.sql")" '.etapes[0].sha256 = $s' "$D3/manifeste.json" > "$T/m" && mv "$T/m" "$D3/manifeste.json"
git -C "$R" commit -qam "manifeste TEST-03 réaligné"
attendre "SHA réalignés après le Go → refus (empreinte ≠ Go)" 1 "a changé depuis le Go" -- "$PORTE" TEST-03 "$E3"

creer_paquet TEST-04 1; valider TEST-04 Eliot; E4="$(empreinte TEST-04)"
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
casser TEST-12 "étape edge_function sans champ fonction → refus" "champ « fonction » manquant" 'jq ".etapes[0].type = \"edge_function\"" manifeste.json > m && mv m manifeste.json'
casser TEST-13 "projet inattendu → refus" "projet inattendu" 'jq ".projet = \"autreprojet\"" manifeste.json > m && mv m manifeste.json'
casser TEST-14 "sha256 absent → refus" "sha256 manquant" 'jq "del(.etapes[0].sha256)" manifeste.json > m && mv m manifeste.json'

creer_paquet TEST-20 2
attendre "niveau 2 sans Go → refus" 1 "paquet non validé" -- "$CTRL" TEST-20
attendre "niveau 2 avec Kevin seul → refus à l'enregistrement" 1 "Go d'Eliot obligatoire" -- "$CTRL" TEST-20 --enregistrer-go "Go TEST-20" --par Kevin
[ ! -e "$R/supabase/changements/TEST-20/validation.json" ] \
  && reussi "Go refusé : aucune validation créée" || rate "Go refusé" "validation créée"
# Même refus pour une validation écrite à la main et commitée.
E20="$(empreinte TEST-20)"
jq -n --arg e "$("$CTRL" TEST-20 --avant-go | sed -n 's/^  empreinte  : //p')" \
  '{id:"TEST-20", go:"Go TEST-20", empreinte_paquet:$e, valide_par:["Kevin"]}' > "$R/supabase/changements/TEST-20/validation.json"
git -C "$R" add -A && git -C "$R" commit -qm "validation Kevin seul"
attendre "niveau 2 sans validation d'Eliot → refus par la porte" 1 "Go d'Eliot obligatoire" -- "$PORTE" TEST-20 "$E20"
creer_paquet TEST-21 2; valider TEST-21 Eliot
attendre "niveau 2 avec Eliot seul → contrôle OK" 0 "contrôles OK" -- "$CTRL" TEST-21
demarrer_serveur ok
attendre "niveau 2 avec Eliot seul → exécution fictive OK" 0 "SUCCÈS : 3 étape" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-21 "$(empreinte TEST-21)"
[ "$(head -n1 "$T/requetes.jsonl" | jq -r '.corps | fromjson | .query')" = "$(cat "$R/supabase/changements/TEST-21/sauvegarde.sql")" ] \
  && reussi "niveau 2 : sauvegarde exécutée avant application" \
  || rate "ordre de sauvegarde" "sauvegarde absente en première étape"
jq -e '.valide_par == ["Eliot"]' "$R/supabase/changements/TEST-21/validation.json" >/dev/null \
  && grep -q '"valide_par":\["Eliot"\]' "$R"/supabase/changements/TEST-21/journal/*-appliquer.log \
  && reussi "validation et reçu : Eliot seul, aucun approbateur ajouté" \
  || rate "approbateurs du reçu" "ne reflètent pas Eliot seul"
creer_paquet TEST-23 2; valider TEST-23 Kevin Eliot
attendre "niveau 2 avec Kevin et Eliot réellement enregistrés → OK" 0 "contrôles OK" -- "$CTRL" TEST-23
creer_paquet TEST-24 1
attendre "niveau 1 avec Kevin seul → refus" 1 "Go d'Eliot obligatoire" -- "$CTRL" TEST-24 --enregistrer-go "Go TEST-24" --par Kevin
attendre "approbateur dupliqué → refus" 1 "dupliqués" -- "$CTRL" TEST-24 --enregistrer-go "Go TEST-24" --par Eliot --par Eliot
creer_paquet TEST-22 2
jq 'del(.sauvegardes)' "$R/supabase/changements/TEST-22/manifeste.json" > "$T/m" && mv "$T/m" "$R/supabase/changements/TEST-22/manifeste.json"
rm "$R/supabase/changements/TEST-22/sauvegarde.sql"; git -C "$R" add -A; git -C "$R" commit -qm x
attendre "niveau 2 sans sauvegarde → refus" 1 "sauvegardes" -- "$CTRL" TEST-22 --avant-go

creer_paquet TEST-25 2
jq 'del(.rollback)' "$R/supabase/changements/TEST-25/manifeste.json" > "$T/m" && mv "$T/m" "$R/supabase/changements/TEST-25/manifeste.json"
git -C "$R" commit -qam "sans rollback"
attendre "niveau 2 sans rollback → refus" 1 "rollback" -- "$CTRL" TEST-25 --avant-go
creer_paquet TEST-26 2
sed -i '/^## Préconditions$/d' "$R/supabase/changements/TEST-26/paquet.md"
git -C "$R" commit -qam "sans préconditions"
attendre "niveau 2 sans préconditions → refus" 1 "Préconditions" -- "$CTRL" TEST-26 --avant-go
creer_paquet TEST-27 2
sed -i '/^## Vérifications après exécution$/d' "$R/supabase/changements/TEST-27/paquet.md"
git -C "$R" commit -qam "sans vérifications"
attendre "niveau 2 sans vérifications → refus" 1 "Vérifications" -- "$CTRL" TEST-27 --avant-go

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
echo "== Edge Functions (même porte)"
mkdir -p "$R/supabase/functions/fn-test" "$R/supabase/functions/fn-multi"
printf "// version precedente (v1)\nDeno.serve(() => new Response('v1'));\n" > "$T/v1.ts"
printf "// version approuvee (v2)\nDeno.serve(() => new Response('v2'));\n" > "$R/supabase/functions/fn-test/index.ts"
printf "export {};\n" > "$R/supabase/functions/fn-multi/index.ts"; printf "export {};\n" > "$R/supabase/functions/fn-multi/util.ts"
git -C "$R" add -A && git -C "$R" commit -qm "fonctions de test"

# creer_paquet_fn <ID> <fonction> [filtre jq appliqué au manifeste] : déploie la
# source du dépôt (fonction.ts), rollback vers v1 (precedente.ts).
creer_paquet_fn() {
  local id="$1" fonction="$2" filtre="${3:-.}" d="$R/supabase/changements/$1"
  mkdir -p "$d"
  if [ -f "$R/supabase/functions/$fonction/index.ts" ]; then cp "$R/supabase/functions/$fonction/index.ts" "$d/fonction.ts"
  else cp "$R/supabase/functions/fn-test/index.ts" "$d/fonction.ts"; fi
  cp "$T/v1.ts" "$d/precedente.ts"
  { echo "# $id"; for s in "Objectif" "Fichiers concernés" "Préconditions" "Impact attendu" \
      "Vérifications après exécution" "Rollback" "Sauvegardes"; do printf '\n## %s\n\nTexte.\n' "$s"; done; } > "$d/paquet.md"
  jq -n --arg id "$id" --arg f "$fonction" --arg a "$(sha "$d/fonction.ts")" --arg p "$(sha "$d/precedente.ts")" '{
      id: $id, niveau: 1, projet: "ssciqjpaibdorvnkkhsk", objectif: "Test Edge Function.", sauvegardes: [],
      etapes:   [{nom: "deployer", type: "edge_function", fonction: $f, fichier: "fonction.ts",   sha256: $a, verify_jwt: true}],
      rollback: [{nom: "revenir",  type: "edge_function", fonction: $f, fichier: "precedente.ts", sha256: $p, verify_jwt: true}]
    }' | jq "$filtre" > "$d/manifeste.json"
  git -C "$R" add -A && git -C "$R" commit -qm "paquet $id"
}

creer_paquet_fn TEST-40 fn-test
attendre "edge_function conforme : contrôle avant Go" 0 "contrôles OK" -- "$CTRL" TEST-40 --avant-go
valider TEST-40 Eliot; E40="$(empreinte TEST-40)"
attendre "edge_function hors session d'écriture → arrêt avant envoi" 3 "absent" -- "$PORTE" TEST-40 "$E40"
demarrer_serveur ok
attendre "edge_function conforme en session d'écriture → déployée et contrôlée" 0 "SUCCÈS : 1 étape" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-40 "$E40"
if [ "$(jq -r '.methode + " " + .chemin' "$T/requetes.jsonl" | tr '\n' '|')" = "POST /v1/projects/ssciqjpaibdorvnkkhsk/functions/deploy?slug=fn-test|GET /v1/projects/ssciqjpaibdorvnkkhsk/functions/fn-test|" ]; then
  reussi "déploiement …/functions/deploy?slug=fn-test puis contrôle de l'état déployé"
else rate "requêtes de déploiement" "$(jq -r '.methode + " " + .chemin' "$T/requetes.jsonl" | tr '\n' '|')"; fi
CORPS="$(head -n1 "$T/requetes.jsonl" | jq -r .corps)"
if grep -qF "version approuvee (v2)" <<<"$CORPS" && grep -qF 'filename="index.ts"' <<<"$CORPS" \
   && grep -qF '"verify_jwt":true' <<<"$CORPS" && grep -qF '"entrypoint_path":"index.ts"' <<<"$CORPS"; then
  reussi "envoie exactement la source approuvée (index.ts) avec verify_jwt=true"
else rate "contenu du déploiement" "source ou métadonnées absentes"; fi
grep -q "DEPLOYE: version 7" "$R"/supabase/changements/TEST-40/journal/*-appliquer.log \
  && reussi "reçu : version déployée journalisée" || rate "reçu de déploiement" "version absente"
grep -qx "  1. deployer — edge_function fn-test — fonction.ts — sha256 $(jq -r '.etapes[0].sha256' "$R/supabase/changements/TEST-40/manifeste.json")" \
  "$R"/supabase/changements/TEST-40/journal/*-appliquer.log \
  && reussi "reçu : PLAN d'une étape edge_function (avec le nom de la fonction)" || rate "PLAN edge_function" "ligne absente"
attendre "double déploiement → refus" 1 "déjà appliqué" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-40 "$E40"
: > "$T/requetes.jsonl"
attendre "rollback vers la version précédente → déployé" 0 "SUCCÈS : 1 étape" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-40 "$E40" --rollback
CORPS="$(head -n1 "$T/requetes.jsonl" | jq -r .corps)"
grep -qF "version precedente (v1)" <<<"$CORPS" && ! grep -qF "version approuvee (v2)" <<<"$CORPS" \
  && reussi "rollback : envoie exactement la version précédente" || rate "rollback Edge Function" "mauvais contenu"

creer_paquet_fn TEST-41 fn-test; valider TEST-41 Eliot; E41="$(empreinte TEST-41)"
demarrer_serveur echec
attendre "erreur de déploiement → arrêt" 1 "HTTP 400" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-41 "$E41"
[ "$(wc -l < "$T/requetes.jsonl")" = 1 ] && reussi "après l'échec du déploiement : aucun contrôle ni étape suivante" \
  || rate "arrêt après échec de déploiement" "$(wc -l < "$T/requetes.jsonl") requêtes"

creer_paquet_fn TEST-42 fn-test; valider TEST-42 Eliot; E42="$(empreinte TEST-42)"
demarrer_serveur jwt_faux
attendre "verify_jwt non confirmé après déploiement → échec" 1 "non confirmés" -- \
  env SWEND_SESSION_ECRITURE=1 SWEND_API_BASE="$BASE" "$PORTE" TEST-42 "$E42"

creer_paquet_fn TEST-43 fn-test
D43="$R/supabase/changements/TEST-43"
printf "// autre contenu\n" >> "$D43/fonction.ts"
jq --arg s "$(sha "$D43/fonction.ts")" '.etapes[0].sha256 = $s' "$D43/manifeste.json" > "$T/m" && mv "$T/m" "$D43/manifeste.json"
git -C "$R" commit -qam "TEST-43 artefact différent de la source"
attendre "hash de l'artefact ≠ source versionnée de la fonction → refus" 1 "ne correspond pas à la source versionnée" -- "$CTRL" TEST-43 --avant-go
creer_paquet_fn TEST-44 fn-test; valider TEST-44 Eliot; E44="$(empreinte TEST-44)"
attendre "artefact Edge Function modifié après le Go → refus" 1 "" -- bash -c "
  printf '// ajout\n' >> '$R/supabase/changements/TEST-44/fonction.ts' && git -C '$R' commit -qam modif &&
  '$PORTE' TEST-44 '$E44'"
creer_paquet_fn TEST-45 fonction-inexistante
attendre "mauvais nom de fonction (inexistante) → refus" 1 "inconnue" -- "$CTRL" TEST-45 --avant-go
creer_paquet_fn TEST-46 fn-test '.etapes[0].fonction = "../fn-test"'
attendre "nom de fonction avec chemin → refus" 1 "nom invalide" -- "$CTRL" TEST-46 --avant-go
creer_paquet_fn TEST-47 fn-multi
attendre "fonction de plusieurs fichiers → refus" 1 "un seul fichier" -- "$CTRL" TEST-47 --avant-go
creer_paquet_fn TEST-48 fn-test 'del(.etapes[0].verify_jwt)'
attendre "verify_jwt absent → refus" 1 "verify_jwt" -- "$CTRL" TEST-48 --avant-go
creer_paquet_fn TEST-49 fn-test '.etapes[0].fonction = "fn-autre"'
attendre "fonction du manifeste ≠ source de l'artefact (fn-autre inconnue) → refus" 1 "inconnue" -- "$CTRL" TEST-49 --avant-go
creer_paquet_fn TEST-50 fn-test; valider TEST-50 Eliot; E50="$(empreinte TEST-50)"
printf "// nouvelle version poussée après le Go\n" >> "$R/supabase/functions/fn-test/index.ts"
git -C "$R" commit -qam "source de fn-test modifiée après le Go"
attendre "source de la fonction modifiée après le Go → refus" 1 "ne correspond pas à la source versionnée" -- "$PORTE" TEST-50 "$E50"

echo
echo "== Dépôt réel : .gitignore des reçus et plan d'un vrai manifeste"
for f in supabase/changements/R1b-01/journal/20261002T175829Z-appliquer.log \
         supabase/changements/XX-01/journal/20990101T000000Z-rollback.log; do
  git -C "$SOURCE" check-ignore -q --no-index "$f" && rate "reçu non ignoré : $f" "ignoré par .gitignore" \
    || reussi "reçu non ignoré : $f"
done
for f in app.log supabase/x.log supabase/changements/XX-01/autre.log supabase/changements/XX-01/journal/sous/x.log; do
  git -C "$SOURCE" check-ignore -q --no-index "$f" && reussi "autre *.log toujours ignoré : $f" \
    || rate "autre *.log toujours ignoré : $f" "n'est plus ignoré"
done
git -C "$SOURCE" ls-files --error-unmatch supabase/changements/R1b-01/journal/20261002T175829Z-appliquer.log >/dev/null 2>&1 \
  && reussi "reçu R1b-01 versionné" || rate "reçu R1b-01 versionné" "absent du dépôt"
PLAN_R1B="$(. "$R/scripts/lib/paquet.sh" && paquet_plan "$SOURCE/supabase/changements/R1b-01/manifeste.json" '[.sauvegardes[]?, .etapes[]]')"
if [ "$(sed -E 's/ — sha256 [0-9a-f]{64}$//' <<<"$PLAN_R1B")" = "$(printf '%s\n' \
     '  1. appliquer — sql_ecriture — appliquer.sql' '  2. verifier — sql_lecture — verifier.sql' \
     '  3. deployer — edge_function send-notification — send-notification.ts' \
     '  4. tests_fonctionnels — sql_ecriture — tests_fonctionnels.sql')" ]; then
  reussi "plan du manifeste R1b-01 : 4 étapes rendues, avec sha256"
else rate "plan du manifeste R1b-01" "$(tr '\n' '|' <<<"$PLAN_R1B")"; fi

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
