#!/bin/bash
# Lance un scénario E2E précis (nom complet ou partiel).
#   qa/run_scenario.sh desistement
#   qa/run_scenario.sh --liste
. "$(dirname "$0")/lib/commun.sh"
. "$QA_ROOT/lib/garde_fou.sh"
qa_garde_fou || exit 1
if [ "$1" = "--liste" ] || [ -z "$1" ]; then cd "$QA_ROOT" && node e2e/run.mjs --liste; exit 0; fi
"$QA_ROOT/stack.sh" start >/dev/null || exit 1
"$QA_ROOT/app/construire_app.sh" || exit 1
cd "$QA_ROOT" && node e2e/run.mjs --scenario "$1"
