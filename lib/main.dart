// ============================================================
// LE PACTE — Version test (mock, sans backend)
// ------------------------------------------------------------
// Tout est stocké en mémoire (AppStore) : rien n'est sauvegardé
// entre deux lancements de l'app. C'est fait exprès : le but est
// de valider les choix d'UX rapidement, pas de construire la
// version finale.
//
// Astuce : utilise le bouton "Moi / Mon ami" en haut de l'écran
// d'accueil pour simuler les deux participants sans avoir besoin
// de deux téléphones.
// ============================================================

import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  runApp(const PacteApp());
}
