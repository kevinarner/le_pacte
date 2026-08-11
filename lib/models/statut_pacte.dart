enum StatutPacte {
  enAttenteChoixDateDestinataire,
  enAttenteChoixDateInitiateur,
  enAttenteReponse,
  confirme,
  maintenu,
  annule,
}

extension StatutPacteLibelle on StatutPacte {
  String get libelle {
    switch (this) {
      case StatutPacte.enAttenteChoixDateDestinataire:
      case StatutPacte.enAttenteChoixDateInitiateur:
        return 'En attente de date';
      case StatutPacte.enAttenteReponse:
        return 'En attente de réponse';
      case StatutPacte.confirme:
        return 'Confirmé';
      case StatutPacte.maintenu:
        return 'Maintenu ✅';
      case StatutPacte.annule:
        return 'Annulé ✗';
    }
  }
}
