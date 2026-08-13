import 'dart:typed_data';

/// Compte utilisateur. `id` est un identifiant interne stable, jamais
/// affiché, qui sert à déterminer "qui je suis" dans un pacte — le nom
/// affiché (prénom/nom) peut changer librement (ex. à l'inscription)
/// sans jamais perturber cette logique.
class Utilisateur {
  final String id;
  String prenom;
  String nom;
  String telephone;
  String email;
  Uint8List? photo;

  Utilisateur({
    required this.id,
    this.prenom = '',
    this.nom = '',
    this.telephone = '',
    this.email = '',
    this.photo,
  });

  String get nomComplet => [prenom, nom].where((s) => s.trim().isNotEmpty).join(' ');
}
