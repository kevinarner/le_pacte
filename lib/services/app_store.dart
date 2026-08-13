import '../models/pacte.dart';
import '../models/utilisateur.dart';

/// Stockage en mémoire (mock — à remplacer par un repository Firebase
/// plus tard). Rien n'est sauvegardé entre deux lancements de l'app.
class AppStore {
  static final List<Pacte> pactes = [];

  // Deux identités simulées pour tester les deux côtés du pacte
  // sans avoir besoin de deux appareils.
  static final Utilisateur moi = Utilisateur(id: 'moi', nom: 'Moi');
  static final Utilisateur ami = Utilisateur(id: 'ami', nom: 'Mon ami');

  static Utilisateur utilisateurCourant(bool perspectiveMoi) => perspectiveMoi ? moi : ami;
  static Utilisateur utilisateurAutre(bool perspectiveMoi) => perspectiveMoi ? ami : moi;

  static int _compteur = 0;
  static String nouvelId() => 'pacte_${_compteur++}';
}
