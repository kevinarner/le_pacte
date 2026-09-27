/// Écran ouvert au clic sur un rappel J-7 / J-3 / J-1 / Jour J (D-021) : la
/// fiche du Swend (participant, titulaire remplacé, remplaçant accepté), ou
/// « Un imprévu ? » pour un titulaire qui cherche encore quelqu'un.
enum DestinationRappel { fiche, imprevu }

/// Traduit la réponse de la base (`destination_rappel`, calculée à
/// l'instant du clic selon l'état ACTUEL du Swend) en écran ; null si la
/// personne n'a plus accès au Swend (ex. désistée).
DestinationRappel? destinationRappelDepuis(String? code) => switch (code) {
  'imprevu' => DestinationRappel.imprevu,
  'fiche' => DestinationRappel.fiche,
  _ => null,
};

/// Web : le clic sur un rappel ouvre l'app avec `?rappel=<pacte_id>` (lien
/// posé par l'Edge Function send-notification). Renvoie ce Swend, ou null.
String? pacteDuLienRappel(Uri adresse) {
  final pacteId = adresse.queryParameters['rappel']?.trim();
  return (pacteId == null || pacteId.isEmpty) ? null : pacteId;
}

/// La même adresse sans `?rappel` : un rechargement de la page ne rouvre
/// pas le rappel.
String adresseSansRappel(Uri adresse) {
  final autres = Map.of(adresse.queryParameters)..remove('rappel');
  final requete = autres.isEmpty ? '' : '?${Uri(queryParameters: autres).query}';
  final ancre = adresse.hasFragment ? '#${adresse.fragment}' : '';
  return '${adresse.path}$requete$ancre';
}
