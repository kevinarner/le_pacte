import 'package:flutter/material.dart';

import 'heure_paris.dart';

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

/// Les formats ci-dessous reçoivent un **instant** de rendez-vous et
/// l'affichent à l'heure de Paris (R2, `heure_paris.dart`), jamais à celle
/// de l'appareil.

/// « mardi 17 novembre 2026 »
String formaterDateEnToutesLettres(DateTime instant) {
  final d = enParis(instant);
  return '${joursSemaine[d.weekday - 1]} ${d.day} ${moisAnnee[d.month - 1]} ${d.year}';
}

/// Seuls les lundi, mardi et mercredi sont autorisés pour un pacte.
bool estJourAutorise(DateTime d) => d.weekday <= DateTime.wednesday;

DateTime prochainJourAutorise(DateTime d) {
  var date = d;
  while (!estJourAutorise(date)) {
    date = date.add(const Duration(days: 1));
  }
  return date;
}

/// Génère la liste des créneaux horaires entre [debut] et [fin] inclus,
/// par pas de [pasMinutes]. Utilisé pour décrire les créneaux réels
/// proposés par un restaurant.
List<TimeOfDay> genererCreneaux(TimeOfDay debut, TimeOfDay fin, {int pasMinutes = 30}) {
  final creneaux = <TimeOfDay>[];
  var minutes = debut.hour * 60 + debut.minute;
  final finMinutes = fin.hour * 60 + fin.minute;
  while (minutes <= finMinutes) {
    creneaux.add(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    minutes += pasMinutes;
  }
  return creneaux;
}

String formaterHeure(TimeOfDay t) => '${t.hour}h${t.minute.toString().padLeft(2, '0')}';

/// « mardi 17 novembre 2026 à 19h00 »
String formaterDateEtHeure(DateTime instant) =>
    '${formaterDateEnToutesLettres(instant)} à ${formaterHeure(heureParis(instant))}';

/// « Mardi 17 novembre · 19h00 »
String formaterJourEtHeureCourt(DateTime instant) {
  final d = enParis(instant);
  final jour = joursSemaine[d.weekday - 1];
  return '${jour[0].toUpperCase()}${jour.substring(1)} ${d.day} '
      '${moisAnnee[d.month - 1]} · ${formaterHeure(heureParis(instant))}';
}

/// « 17/11/2026 » (jour de Paris d'un instant)
String formaterJourCourtChiffres(DateTime instant) {
  final d = enParis(instant);
  return '${d.day}/${d.month}/${d.year}';
}

/// « 17 novembre » (jour de Paris d'un instant)
String formaterJourEtMois(DateTime instant) {
  final d = enParis(instant);
  return '${d.day} ${moisAnnee[d.month - 1]}';
}

const _moisCourts = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

/// "10 nov. · 09:42", à l'heure de Paris — horodatage des événements d'une
/// conversation.
String formaterHorodatage(DateTime d) {
  final l = enParis(d);
  return '${l.day} ${_moisCourts[l.month - 1]} · '
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
