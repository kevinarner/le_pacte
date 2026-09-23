/// Un fil de discussion vu depuis l'écran Messagerie unifié — que je sois
/// titulaire (parlant à mon remplaçant) ou remplaçant (parlant à mon
/// titulaire), peu importe le pacte d'origine.
class FilDeDiscussion {
  final String remplacantId;
  final String nomInterlocuteur;

  /// Connu d'avance côté titulaire (déjà dans son formulaire de
  /// remplaçants) — laissé à null côté remplaçant, récupéré alors par
  /// ChatScreen via une fonction serveur dédiée.
  final String? telephoneInterlocuteur;

  final String? dernierMessage;
  final DateTime? dateDernierMessage;

  /// True si c'est moi qui ai envoyé le dernier message du fil — sert à
  /// repérer un message de l'interlocuteur pas encore "vu" (au sens
  /// large : pas de vrai suivi lu/non-lu, juste "le dernier mot n'est
  /// pas de moi").
  final bool dernierMessageDeMoi;

  /// La date retenue du pacte concerné par ce fil, et le nom du
  /// restaurant — affichés sous le nom de l'interlocuteur pour situer la
  /// conversation. Nulle si aucune date n'est encore retenue.
  final DateTime? dateConcernee;
  final String? restaurantNom;

  /// Le nom de l'autre titulaire du Swend concerné par ce fil (distinct
  /// de [nomInterlocuteur], qui peut être la personne de confiance et
  /// non l'autre partie) — sert à situer la notification ("Swend avec
  /// David · ...") sur l'accueil.
  final String? autrePartieNom;

  FilDeDiscussion({
    required this.remplacantId,
    required this.nomInterlocuteur,
    this.telephoneInterlocuteur,
    this.dernierMessage,
    this.dateDernierMessage,
    this.dernierMessageDeMoi = true,
    this.dateConcernee,
    this.restaurantNom,
    this.autrePartieNom,
  });
}
