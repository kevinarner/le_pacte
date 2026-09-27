#!/bin/bash
# Smoke E2E : le parcours principal de Swend, de bout en bout, à lancer
# après chaque lot important. Démarre la pile et (re)construit l'app QA au
# besoin.
. "$(dirname "$0")/lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1
"$QA_ROOT/stack.sh" start >/dev/null || exit 1
"$QA_ROOT/app/construire_app.sh" || exit 1
cd "$QA_ROOT" && node e2e/run.mjs --suite smoke "$@"
