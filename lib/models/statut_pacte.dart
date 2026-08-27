enum StatutPacte {
  enAttenteChoixDateDestinataire,
  enAttenteChoixDateInitiateur,
  enAttenteReponse,
  confirme,
  maintenu,
  annule,

  /// Les deux côtés ont délégué leur présence à un remplaçant : le
  /// pacte est annulé automatiquement, sans jamais révéler qui a été
  /// choisi de part et d'autre. Basculé uniquement par un déclencheur
  /// côté base (voir annuler_si_double_absence()), jamais par l'app.
  annuleDoubleAbsence,
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
      case StatutPacte.annuleDoubleAbsence:
        return 'Annulé ✗';
    }
  }
}
