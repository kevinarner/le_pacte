import 'package:flutter/material.dart';

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

TimeOfDay heureDe(DateTime d) => TimeOfDay(hour: d.hour, minute: d.minute);

DateTime avecHeure(DateTime jour, TimeOfDay heure) =>
    DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute);

String formaterHeure(TimeOfDay t) => '${t.hour}h${t.minute.toString().padLeft(2, '0')}';

String formaterDateEtHeure(DateTime d) =>
    '${formaterDateEnToutesLettres(d)} à ${formaterHeure(heureDe(d))}';
