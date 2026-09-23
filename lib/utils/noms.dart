/// Le prénom seul à partir d'un nom complet ("Kevin Arner" → "Kevin") —
/// utilisé pour les badges et notifications, plus direct et humain
/// qu'un nom complet.
String prenomDe(String nomComplet) =>
    nomComplet.trim().split(RegExp(r'\s+')).first;
