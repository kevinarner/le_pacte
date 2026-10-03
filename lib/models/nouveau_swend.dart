// « Faire un nouveau Swend » depuis un chat après le Swend (D-023c) :
// éléments sans dépendance à l'interface.

/// Personne d'un chat après le Swend avec qui faire un nouveau Swend :
/// identifiant de participant et prénom, jamais de numéro (D-024).
class AvecQuiDepuisChat {
  final String chatId;
  final String participantId;
  final String prenom;

  const AvecQuiDepuisChat({
    required this.chatId,
    required this.participantId,
    required this.prenom,
  });
}

enum EtapeCreation { avecQui, quandEtOu, remplacants }

/// Les étapes de la création : depuis un chat après le Swend, la personne
/// est connue et « Avec qui ? » est sauté.
List<EtapeCreation> etapesCreation({required bool depuisChat}) => [
  if (!depuisChat) EtapeCreation.avecQui,
  EtapeCreation.quandEtOu,
  EtapeCreation.remplacants,
];
