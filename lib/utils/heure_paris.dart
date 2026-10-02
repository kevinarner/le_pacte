import 'package:flutter/material.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Convention temporelle de Swend (R2) — seul module de conversion de l'app.
///
/// - Heure métier = heure murale d'Europe/Paris (créneaux du restaurant),
///   quel que soit le fuseau de l'appareil.
/// - Un rendez-vous (date proposée, date retenue) est un **instant absolu** :
///   un `DateTime` UTC dans l'app, `timestamptz` ou chaîne ISO 8601 avec
///   fuseau en base. Échange app ↔ base : toujours [isoInstant] (suffixe Z).
/// - Un **jour civil** (calendrier, date minimale) est un `DateTime` dont
///   seuls année, mois et jour comptent (`DateTime(a, m, j)`).
/// - Conversion heure de Paris ↔ instant : ici seulement, avec les données
///   IANA du package `timezone` (jamais `toLocal()`, jamais un `DateTime`
///   local pour une heure de Swend).
///
/// Données `latest_10y` (≈ 5 ans avant et après leur génération) : toute
/// heure hors de leur couverture est refusée ([HorsCouvertureFuseau]) plutôt
/// que convertie avec un décalage faux ; un test impose une marge de 3 ans
/// (mettre à jour le package `timezone` avant qu'il échoue).

final tz.Location _paris = () {
  tzdata.initializeTimeZones();
  return tz.getLocation('Europe/Paris');
}();

/// Fin de couverture des données de fuseau pour Europe/Paris (dernier
/// changement d'heure connu).
final DateTime finCouvertureParis = DateTime.fromMillisecondsSinceEpoch(
  _paris.transitionAt.last,
  isUtc: true,
);

class HorsCouvertureFuseau implements Exception {
  final DateTime instant;
  HorsCouvertureFuseau(this.instant);
  @override
  String toString() =>
      'Heure hors de la couverture des données de fuseau ($instant) : '
      'mettre à jour le package timezone.';
}

void _verifierCouverture(DateTime instant) {
  if (instant.isAfter(finCouvertureParis)) {
    throw HorsCouvertureFuseau(instant);
  }
}

/// Instant → date et heure murales de Paris (champs year…minute, weekday).
tz.TZDateTime enParis(DateTime instant) {
  _verifierCouverture(instant);
  return tz.TZDateTime.from(instant, _paris);
}

/// Jour civil de Paris d'un instant.
DateTime jourParis(DateTime instant) {
  final p = enParis(instant);
  return DateTime(p.year, p.month, p.day);
}

/// Aujourd'hui à Paris (jour civil).
DateTime aujourdhuiParis([DateTime? maintenant]) =>
    jourParis(maintenant ?? DateTime.now());

/// Instant (UTC) d'une heure murale de Paris : [jour] est un jour civil
/// (seuls année, mois et jour sont lus, quel que soit son fuseau).
DateTime instantParis(DateTime jour, TimeOfDay heure) {
  final instant = tz.TZDateTime(
    _paris,
    jour.year,
    jour.month,
    jour.day,
    heure.hour,
    heure.minute,
  ).toUtc();
  _verifierCouverture(instant);
  return DateTime.fromMillisecondsSinceEpoch(
    instant.millisecondsSinceEpoch,
    isUtc: true,
  );
}

/// Heure murale de Paris d'un instant.
TimeOfDay heureParis(DateTime instant) {
  final p = enParis(instant);
  return TimeOfDay(hour: p.hour, minute: p.minute);
}

/// Même jour de Paris, autre heure murale.
DateTime avecHeureParis(DateTime instant, TimeOfDay heure) =>
    instantParis(jourParis(instant), heure);

/// Forme canonique envoyée à la base : instant UTC, ISO 8601, suffixe Z
/// (« 2026-11-17T18:00:00.000Z »).
String isoInstant(DateTime instant) => instant.toUtc().toIso8601String();

/// Lit un instant venant de la base. Une chaîne avec fuseau (forme
/// canonique, ou `timestamptz` renvoyé par PostgREST) est un instant. Une
/// chaîne sans fuseau (ancien format de `dates_proposees`, antérieur à R2)
/// est lue comme l'heure murale de Paris qu'elle a toujours représentée.
DateTime lireInstant(String valeur) {
  final d = DateTime.parse(valeur);
  if (d.isUtc) return d;
  return instantParis(d, TimeOfDay(hour: d.hour, minute: d.minute));
}
