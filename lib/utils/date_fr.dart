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
