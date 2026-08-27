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

  /// Identifiant du compte de ce remplaçant, une fois qu'il en a créé
  /// un avec ce numéro de téléphone — null tant qu'il n'a pas rejoint
  /// l'app. Le chat n'est possible qu'une fois ce champ renseigné.
  String? profilId;

  Remplacant({
    this.id,
    this.prenom = '',
    this.nom = '',
    this.telephone = '',
    this.email = '',
    this.selectionne = false,
    this.profilId,
  });

  bool get estRempli =>
      prenom.trim().isNotEmpty && nom.trim().isNotEmpty && telephone.trim().isNotEmpty;

  String get nomComplet => [prenom, nom].where((s) => s.trim().isNotEmpty).join(' ');
}
