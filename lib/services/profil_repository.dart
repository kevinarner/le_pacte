import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';

/// Mise à jour des informations de compte (téléphone, email, mot de
/// passe) — persistées réellement dans Supabase.
class ProfilRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Met à jour le téléphone dans `profiles`. Le message d'erreur, s'il
  /// contient "telephone" et "duplicate"/"unique", signale que ce numéro
  /// est déjà associé à un autre compte — même contrainte qu'à
  /// l'inscription.
  static Future<void> modifierTelephone(String telephone) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('profiles').update({'telephone': telephone.trim()}).eq('id', userId);
  }

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
