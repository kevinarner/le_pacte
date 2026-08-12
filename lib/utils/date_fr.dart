import 'package:flutter/material.dart';

import '../models/type_repas.dart';

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

/// Créneaux horaires autorisés selon le type de repas, par pas de 30 min :
/// déjeuner de 12h00 à 14h30, dîner de 19h00 à 22h00.
List<TimeOfDay> creneauxPourType(TypeRepas type) {
  final debut = type == TypeRepas.dejeuner
      ? const TimeOfDay(hour: 12, minute: 0)
      : const TimeOfDay(hour: 19, minute: 0);
  final fin = type == TypeRepas.dejeuner
      ? const TimeOfDay(hour: 14, minute: 30)
      : const TimeOfDay(hour: 22, minute: 0);
  final creneaux = <TimeOfDay>[];
  var minutes = debut.hour * 60 + debut.minute;
  final finMinutes = fin.hour * 60 + fin.minute;
  while (minutes <= finMinutes) {
    creneaux.add(TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    minutes += 30;
  }
  return creneaux;
}

TimeOfDay heureDe(DateTime d) => TimeOfDay(hour: d.hour, minute: d.minute);

DateTime avecHeure(DateTime jour, TimeOfDay heure) =>
    DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute);

String formaterHeure(TimeOfDay t) => '${t.hour}h${t.minute.toString().padLeft(2, '0')}';

String formaterDateEtHeure(DateTime d) =>
    '${formaterDateEnToutesLettres(d)} à ${formaterHeure(heureDe(d))}';
