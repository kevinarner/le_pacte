#!/bin/bash
# Build web QA de la VRAIE app, pointée vers la pile locale.
# Le dépôt n'est jamais modifié : les sources sont copiées dans
# qa/.work/app/ et seule cette copie est adaptée (adresse et clé de l'API
# locale, attente Firebase bornée). La build est ensuite vérifiée : elle ne
# doit contenir aucune trace de la production.
# Refaite seulement si le code a changé (empreinte des sources).
. "$(dirname "$0")/../lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1

COPIE="$QA_WORK/app"; SORTIE="$QA_WORK/build"
empreinte() {
  (cd "$REPO_ROOT" && find lib web assets pubspec.yaml pubspec.lock -type f -print0 | sort -z | xargs -0 sha256sum; \
   sha256sum "$QA_ROOT/app/construire_app.sh" "$QA_ROOT/config.env") | sha256sum | cut -c1-16
}
E="$(empreinte)"
if [ "$1" != "--forcer" ] && [ -f "$SORTIE/.empreinte" ] && [ "$(cat "$SORTIE/.empreinte")" = "$E" ]; then
  echo "Build QA à jour ($E)."; exit 0
fi

qa_titre "Build web QA (sources $E)"
rm -rf "$COPIE"; mkdir -p "$COPIE"
(cd "$REPO_ROOT" && tar cf - lib web assets pubspec.yaml pubspec.lock analysis_options.yaml) | (cd "$COPIE" && tar xf -)

# Jeton "anon" local, signé avec le secret de la pile QA.
ANON="$(node -e "
const c=require('crypto');const b=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
const h=b({alg:'HS256',typ:'JWT'}),p=b({role:'anon',iss:'swend-qa',iat:1700000000,exp:2100000000});
console.log(h+'.'+p+'.'+c.createHmac('sha256',process.env.QA_JWT_SECRET).update(h+'.'+p).digest('base64url'))")"

QA_ANON="$ANON" python3 - "$COPIE" <<'PY' || exit 1
import os, re, sys
copie = sys.argv[1]
p = os.path.join(copie, 'lib/constants.dart'); s = open(p).read()
s, n1 = re.subn(r"const supabaseUrl = '[^']*';", "const supabaseUrl = '%s';" % os.environ['QA_API_URL'], s)
s, n2 = re.subn(r"const supabaseAnonKey =\s*'[^']*';", "const supabaseAnonKey = '%s';" % os.environ['QA_ANON'], s)
if n1 != 1 or n2 != 1: sys.exit('constants.dart : adresse ou clé introuvable, adaptation impossible')
open(p, 'w').write(s)
p = os.path.join(copie, 'lib/main.dart'); s = open(p).read()
ancien = "await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);"
if ancien not in s: sys.exit('main.dart : initialisation Firebase introuvable')
s = s.replace(ancien, "await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).timeout(const Duration(seconds: 2));")
open(p, 'w').write(s)
PY

(cd "$COPIE" && flutter pub get --offline > "$QA_LOGS/build_app.log" 2>&1 || flutter pub get >> "$QA_LOGS/build_app.log" 2>&1) || { qa_erreur "pub get"; exit 1; }
rm -rf "$SORTIE"
(cd "$COPIE" && flutter build web --release --no-web-resources-cdn -o "$SORTIE" >> "$QA_LOGS/build_app.log" 2>&1) \
  || { qa_erreur "build Flutter (voir $QA_LOGS/build_app.log)"; exit 1; }
qa_garde_fou_build "$SORTIE" || { rm -rf "$SORTIE"; exit 1; }
grep -rqs "$QA_API_URL" "$SORTIE" || { qa_erreur "la build ne pointe pas vers $QA_API_URL"; rm -rf "$SORTIE"; exit 1; }
echo "$E" > "$SORTIE/.empreinte"
echo "Build QA prête : $SORTIE"
