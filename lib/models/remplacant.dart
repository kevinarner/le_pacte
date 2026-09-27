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

  /// La personne, simplement prévue, a indiqué d'elle-même "Je ne serai
  /// pas disponible" (réversible : "Je suis finalement disponible").
  /// Distinct de [demandeStatut] : aucune demande n'existe dans ce cas.
  bool indisponibleSpontanement;

  Remplacant({
    this.id,
    this.prenom = '',
    this.nom = '',
    this.telephone = '',
    this.email = '',
    this.selectionne = false,
    this.profilId,
    this.demandeStatut,
    this.indisponibleSpontanement = false,
  });

  /// Ne peut pas être sollicitée pour l'instant : refus, clôture ou
  /// désistement (définitifs pour la tentative en cours), ou
  /// indisponibilité spontanée (réversible par la personne elle-même).
  bool get estIndisponible =>
      demandeStatut.estIndisponible || indisponibleSpontanement;

  /// Simplement prévue, sans demande : peut dire "Je ne serai pas disponible".
  bool get peutSeDeclarerIndisponible =>
      !selectionne && demandeStatut == null && !indisponibleSpontanement;

  bool get estRempli =>
      prenom.trim().isNotEmpty &&
      nom.trim().isNotEmpty &&
      telephone.trim().isNotEmpty;

  /// Les personnes qui ont déjà un compte Swend d'abord, puis les autres,
  /// en gardant l'ordre existant dans chaque groupe.
  static List<Remplacant> comptesDAbord(Iterable<Remplacant> liste) => [
    ...liste.where((r) => r.profilId != null),
    ...liste.where((r) => r.profilId == null),
  ];

  String get nomComplet =>
      [prenom, nom].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
}
