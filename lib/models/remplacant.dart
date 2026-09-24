import 'demande_statut.dart';

class Remplacant {
  /// Identifiant de la ligne en base — null tant qu'il n'a pas encore
  /// été enregistré côté serveur.
  String? id;
  String prenom;
  String nom;
  String telephone;
  String email;

  /// True si c'est celui à qui la présence a été déléguée — devient
  /// true uniquement quand cette personne accepte une demande (voir
  /// [demandeStatut]), jamais directement au clic du titulaire.
  bool selectionne;

  /// Identifiant du compte de ce remplaçant, une fois qu'il en a créé
  /// un avec ce numéro de téléphone — null tant qu'il n'a pas rejoint
  /// l'app. Le chat n'est possible qu'une fois ce champ renseigné.
  String? profilId;

  /// Où en est une éventuelle demande "Un imprévu ?" envoyée à cette
  /// personne — null si elle n'a jamais été sollicitée pour la
  /// tentative en cours.
  DemandeStatut? demandeStatut;

  Remplacant({
    this.id,
    this.prenom = '',
    this.nom = '',
    this.telephone = '',
    this.email = '',
    this.selectionne = false,
    this.profilId,
    this.demandeStatut,
  });

  bool get estRempli =>
      prenom.trim().isNotEmpty &&
      nom.trim().isNotEmpty &&
      telephone.trim().isNotEmpty;

  String get nomComplet =>
      [prenom, nom].where((s) => s.trim().isNotEmpty).join(' ');
}
