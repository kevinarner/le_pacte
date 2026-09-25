import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';

/// Mise à jour des informations de compte (email, mot de passe) —
/// persistées réellement dans Supabase. Le numéro de téléphone est figé
/// après l'inscription (V1) : la base refuse de le modifier depuis l'app.
class ProfilRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Déclenche le changement d'email Supabase Auth : un email de
  /// confirmation est envoyé à la nouvelle adresse, le changement ne
  /// prend effet qu'une fois ce lien cliqué.
  static Future<void> modifierEmail(String email) async {
    await _client.auth.updateUser(
      UserAttributes(email: email.trim()),
      emailRedirectTo: lienTelechargementApp,
    );
  }

  static Future<void> modifierMotDePasse(String motDePasse) async {
    await _client.auth.updateUser(UserAttributes(password: motDePasse));
  }
}
