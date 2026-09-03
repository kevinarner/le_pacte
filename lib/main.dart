import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'constants.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // ignore: avoid_print
    print('[Pakt] Firebase initialisé avec succès.');
  } catch (e) {
    // Les notifications ne doivent jamais empêcher le reste de l'app de
    // fonctionner (réseau bloqué, extension de blocage de pub, etc.).
    // ignore: avoid_print
    print("[Pakt] Firebase indisponible, l'app continue sans notifications : $e");
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const PacteApp());
}
