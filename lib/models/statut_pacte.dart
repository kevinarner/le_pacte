enum StatutPacte {
  enAttenteReponse,
  refuseContreProposition,
  accepteEnAttenteClassement,
  confirme,
  maintenu,
  annule,
}

extension StatutPacteLibelle on StatutPacte {
  String get libelle {
    switch (this) {
      case StatutPacte.enAttenteReponse:
        return 'En attente de réponse';
      case StatutPacte.refuseContreProposition:
        return 'Contre-proposition envoyée';
      case StatutPacte.accepteEnAttenteClassement:
        return 'Accepté — classement des restaurants à faire';
      case StatutPacte.confirme:
        return 'Confirmé';
      case StatutPacte.maintenu:
        return 'Maintenu ✅';
      case StatutPacte.annule:
        return 'Annulé ✗';
    }
  }
}
