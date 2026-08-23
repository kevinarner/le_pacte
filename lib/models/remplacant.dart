class Remplacant {
  /// Identifiant de la ligne en base — null tant qu'il n'a pas encore
  /// été enregistré côté serveur.
  String? id;
  String prenom;
  String nom;
  String telephone;
  String email;

  /// True si c'est celui à qui la présence a été déléguée.
  bool selectionne;

  Remplacant({
    this.id,
    this.prenom = '',
    this.nom = '',
    this.telephone = '',
    this.email = '',
    this.selectionne = false,
  });

  bool get estRempli => prenom.trim().isNotEmpty && nom.trim().isNotEmpty;

  String get nomComplet => [prenom, nom].where((s) => s.trim().isNotEmpty).join(' ');
}
