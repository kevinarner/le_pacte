// ============================================================
// LE PACTE
// ------------------------------------------------------------
// Astuce : utilise le bouton "Moi / Mon ami" en haut de l'écran
// d'accueil pour simuler les deux participants sans avoir besoin
// de deux téléphones.
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const PacteApp());
}
