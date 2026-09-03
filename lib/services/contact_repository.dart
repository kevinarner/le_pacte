import 'package:supabase_flutter/supabase_flutter.dart';

/// Envoi des suggestions de restaurant et des messages du formulaire
/// "Nous contacter" — écriture seule, les soumissions sont consultées
/// directement dans Supabase, pas depuis l'app.
class ContactRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> suggererRestaurant({required String nom, String? lien}) async {
    await _client.from('suggestions_restaurant').insert({
      'profile_id': _client.auth.currentUser!.id,
      'nom': nom.trim(),
      if (lien != null && lien.trim().isNotEmpty) 'lien': lien.trim(),
    });
  }

  static Future<void> envoyerMessageContact({
    required String objet,
    required String message,
  }) async {
    await _client.from('messages_contact').insert({
      'profile_id': _client.auth.currentUser!.id,
      'objet': objet.trim(),
      'message': message.trim(),
    });
  }
}
