import '../models/pacte.dart';
import '../models/remplacant.dart';

/// Stockage en mémoire (mock — à remplacer par un repository Firebase
/// plus tard). Rien n'est sauvegardé entre deux lancements de l'app.
class AppStore {
  static final List<Pacte> pactes = [];

  // Deux identités simulées pour tester les deux côtés du pacte
  // sans avoir besoin de deux appareils.
  static final List<Remplacant> remplacantsMoi = [
    Remplacant(nom: 'Camille'),
    Remplacant(nom: 'Sacha'),
    Remplacant(nom: 'Lou'),
  ];
  static final List<Remplacant> remplacantsAmi = [
    Remplacant(nom: 'Nino'),
    Remplacant(nom: 'Alex'),
    Remplacant(nom: 'Jules'),
  ];

  static int _compteur = 0;
  static String nouvelId() => 'pacte_${_compteur++}';
}
