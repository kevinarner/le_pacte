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

  /// La date retenue du pacte concerné par ce fil, et le nom du
  /// restaurant — affichés sous le nom de l'interlocuteur pour situer la
  /// conversation. Nulle si aucune date n'est encore retenue.
  final DateTime? dateConcernee;
  final String? restaurantNom;

  FilDeDiscussion({
    required this.remplacantId,
    required this.nomInterlocuteur,
    this.telephoneInterlocuteur,
    this.dernierMessage,
    this.dateDernierMessage,
    this.dateConcernee,
    this.restaurantNom,
  });
}
