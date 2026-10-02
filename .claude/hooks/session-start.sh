#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Session « Swend – écriture prod » : stérile, aucune installation ni
# téléchargement de dépendances en présence du jeton d'écriture (CLAUDE.md).
if [ "${SWEND_SESSION_ECRITURE:-}" = "1" ]; then
  echo "Session d'écriture production : installation Flutter ignorée."
  exit 0
fi

FLUTTER_HOME="$HOME/flutter"

if [ ! -d "$FLUTTER_HOME" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"
echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

flutter config --no-analytics --enable-web >/dev/null
flutter precache --web >/dev/null

cd "$CLAUDE_PROJECT_DIR"
flutter pub get
