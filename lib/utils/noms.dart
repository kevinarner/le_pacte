/// Le prénom seul à partir d'un nom complet ("Kevin Arner" → "Kevin") —
/// utilisé pour les badges et notifications, plus direct et humain
/// qu'un nom complet.
String prenomDe(String nomComplet) =>
    nomComplet.trim().split(RegExp(r'\s+')).first;

/// "de David" / "d'Eliot" — élision devant une voyelle ou un h.
String deNom(String nom) {
  final n = nom.trim();
  if (n.isEmpty) return 'de';
  return RegExp(r'^[aeiouyhàâäéèêëîïôöùûüAEIOUYHÀÂÄÉÈÊËÎÏÔÖÙÛÜ]').hasMatch(n)
      ? "d'$n"
      : 'de $n';
}
