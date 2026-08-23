import '../models/utilisateur.dart';

/// "moi" est l'identité réellement connectée — voir LoginScreen, qui
/// remplace cette valeur par le vrai compte Supabase après connexion.
class AppStore {
  static Utilisateur moi = Utilisateur(id: '', nom: '');
}
