import '../models/pacte.dart';
import '../models/restaurant.dart';

/// Additionne les rangs (0 = préféré). En cas d'égalité,
/// priorité au n°1 du destinataire.
Restaurant calculerRestaurantElu(Pacte pacte) {
  final n = pacte.restaurantsProposes.length;
  final scores = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final rangInitiateur = pacte.classementInitiateur!.indexOf(i);
    final rangDestinataire = pacte.classementDestinataire!.indexOf(i);
    scores[i] = rangInitiateur + rangDestinataire;
  }
  int meilleurIndex = 0;
  for (int i = 1; i < n; i++) {
    if (scores[i] < scores[meilleurIndex]) {
      meilleurIndex = i;
    } else if (scores[i] == scores[meilleurIndex]) {
      // égalité : priorité au n°1 du destinataire
      final prefDest = pacte.classementDestinataire!.first;
      if (prefDest == i) meilleurIndex = i;
    }
  }
  return pacte.restaurantsProposes[meilleurIndex];
}
