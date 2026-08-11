class Remplacant {
  String prenom;
  String nom;
  String telephone;
  String email;

  Remplacant({this.prenom = '', this.nom = '', this.telephone = '', this.email = ''});

  bool get estRempli => prenom.trim().isNotEmpty && nom.trim().isNotEmpty;

  String get nomComplet => [prenom, nom].where((s) => s.trim().isNotEmpty).join(' ');
}
