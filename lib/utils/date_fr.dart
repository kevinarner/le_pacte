const joursSemaine = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const moisAnnee = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String formaterDateEnToutesLettres(DateTime d) =>
    '${joursSemaine[d.weekday - 1]} ${d.day} ${moisAnnee[d.month - 1]} ${d.year}';

/// Seuls les lundi, mardi et mercredi sont autorisés pour un pacte.
bool estJourAutorise(DateTime d) => d.weekday <= DateTime.wednesday;

DateTime prochainJourAutorise(DateTime d) {
  var date = d;
  while (!estJourAutorise(date)) {
    date = date.add(const Duration(days: 1));
  }
  return date;
}
