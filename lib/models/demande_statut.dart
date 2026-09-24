/// Où en est une demande faite à une personne de confiance pour
/// prendre la place du titulaire ("Un imprévu ?"). Absent (`null` sur
/// [Remplacant.demandeStatut]) tant qu'elle n'a jamais été sollicitée
/// pour la tentative en cours.
enum DemandeStatut {
  /// Envoyée, en attente de réponse.
  envoyee,

  /// La personne a refusé.
  refusee,

  /// Quelqu'un d'autre a accepté entre-temps : cette demande n'a plus
  /// d'objet.
  cloturee,

  /// La personne a accepté — elle devient celle qui se présentera.
  acceptee,
}
