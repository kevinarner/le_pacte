/// Où en est une demande faite à une personne de confiance pour
/// prendre la place du titulaire ("Un imprévu ?"). Absent (`null` sur
/// [Remplacant.demandeStatut]) tant qu'elle n'a jamais été sollicitée
/// pour la tentative en cours — ou après l'annulation d'une demande par
/// le titulaire, ou la réouverture de la recherche après un désistement.
enum DemandeStatut {
  /// Envoyée, en attente de réponse.
  envoyee,

  /// La personne a refusé.
  refusee,

  /// Quelqu'un d'autre a accepté entre-temps, ou la personne a pris la
  /// place de l'autre participant du même Swend : elle n'est plus
  /// sollicitable ici.
  cloturee,

  /// La personne a accepté — elle devient celle qui se présentera.
  acceptee,

  /// Elle avait accepté puis ne peut finalement plus venir.
  desistee,
}

extension DemandeStatutAffichage on DemandeStatut? {
  /// Refusée, clôturée ou désistée : affichées toutes les trois
  /// "Indisponible", sans jamais dire pourquoi.
  bool get estIndisponible =>
      this == DemandeStatut.refusee ||
      this == DemandeStatut.cloturee ||
      this == DemandeStatut.desistee;
}
