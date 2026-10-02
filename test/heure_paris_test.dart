import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/utils/date_fr.dart';
import 'package:le_pacte/utils/heure_paris.dart';

/// Convention temporelle (R2) : heure métier = Europe/Paris, rendez-vous =
/// instant UTC, conversion seulement dans `heure_paris.dart`. Ces tests sont
/// rejoués par `qa/run_metier.sh` avec l'appareil en UTC, Europe/Paris,
/// America/New_York et Pacific/Auckland : les résultats ne doivent jamais
/// dépendre du fuseau de l'appareil.
void main() {
  DateTime paris(int a, int m, int j, int h, [int mi = 0]) =>
      instantParis(DateTime(a, m, j), TimeOfDay(hour: h, minute: mi));

  group('heure murale de Paris → instant', () {
    final cas = <String, (DateTime, DateTime)>{
      'hiver : 17/11/2026 19:00': (paris(2026, 11, 17, 19), DateTime.utc(2026, 11, 17, 18)),
      'été : 06/07/2027 19:00': (paris(2027, 7, 6, 19), DateTime.utc(2027, 7, 6, 17)),
      'lendemain du passage à l’heure d’hiver : 26/10/2026 19:00': (paris(2026, 10, 26, 19), DateTime.utc(2026, 10, 26, 18)),
      'lendemain du passage à l’heure d’été : 29/03/2027 19:00': (paris(2027, 3, 29, 19), DateTime.utc(2027, 3, 29, 17)),
      'jour du passage à l’heure d’hiver : 25/10/2026 18:00 (rappel J-1)': (paris(2026, 10, 25, 18), DateTime.utc(2026, 10, 25, 17)),
      'jour du passage à l’heure d’été : 28/03/2027 18:00 (rappel J-1)': (paris(2027, 3, 28, 18), DateTime.utc(2027, 3, 28, 16)),
      'veille du passage à l’heure d’hiver : 24/10/2026 21:45': (paris(2026, 10, 24, 21, 45), DateTime.utc(2026, 10, 24, 19, 45)),
      'déjeuner d’hiver : 17/11/2026 12:30': (paris(2026, 11, 17, 12, 30), DateTime.utc(2026, 11, 17, 11, 30)),
    };
    cas.forEach((nom, c) {
      test(nom, () {
        expect(c.$1, c.$2);
        expect(c.$1.isUtc, isTrue);
      });
    });
  });

  test('aller-retour : jour et heure de Paris retrouvés à l’identique', () {
    for (final c in [(2026, 11, 17, 19, 0), (2027, 7, 6, 21, 45), (2026, 10, 25, 18, 0), (2027, 3, 28, 18, 0), (2027, 3, 29, 12, 0)]) {
      final i = paris(c.$1, c.$2, c.$3, c.$4, c.$5);
      expect(jourParis(i), DateTime(c.$1, c.$2, c.$3));
      expect(heureParis(i), TimeOfDay(hour: c.$4, minute: c.$5));
    }
  });

  test('changer l’heure garde le jour de Paris', () {
    final i = paris(2026, 11, 17, 19);
    expect(avecHeureParis(i, const TimeOfDay(hour: 21, minute: 30)), DateTime.utc(2026, 11, 17, 20, 30));
    expect(avecHeureParis(paris(2027, 7, 6, 19), const TimeOfDay(hour: 12, minute: 0)), DateTime.utc(2027, 7, 6, 10));
  });

  test('jour de Paris ≠ jour UTC autour de minuit', () {
    expect(jourParis(DateTime.utc(2026, 10, 15, 22, 30)), DateTime(2026, 10, 16));
    expect(jourParis(DateTime.utc(2026, 11, 16, 23, 30)), DateTime(2026, 11, 17));
    expect(aujourdhuiParis(DateTime.utc(2026, 12, 31, 23, 30)), DateTime(2027, 1, 1));
  });

  group('échange avec la base', () {
    test('envoi : instant UTC, ISO 8601, suffixe Z', () {
      expect(isoInstant(paris(2026, 11, 17, 19)), '2026-11-17T18:00:00.000Z');
      expect(isoInstant(paris(2027, 7, 6, 19)), '2027-07-06T17:00:00.000Z');
    });
    test('lecture : forme canonique, timestamptz de PostgREST, offset explicite', () {
      final attendu = DateTime.utc(2026, 11, 17, 18);
      expect(lireInstant('2026-11-17T18:00:00.000Z'), attendu);
      expect(lireInstant('2026-11-17T18:00:00+00:00'), attendu);
      expect(lireInstant('2026-11-17T19:00:00+01:00'), attendu);
    });
    test('lecture d’une ancienne chaîne sans fuseau : heure murale de Paris', () {
      expect(lireInstant('2026-11-17T19:00:00.000'), DateTime.utc(2026, 11, 17, 18));
      expect(lireInstant('2027-07-06T19:00:00.000'), DateTime.utc(2027, 7, 6, 17));
    });
  });

  group('affichage à l’heure de Paris', () {
    test('Swend du 17/11 à 19h', () {
      final i = DateTime.utc(2026, 11, 17, 18);
      expect(formaterDateEtHeure(i), 'mardi 17 novembre 2026 à 19h00');
      expect(formaterJourEtHeureCourt(i), 'Mardi 17 novembre · 19h00');
      expect(formaterJourEtMois(i), '17 novembre');
      expect(formaterJourCourtChiffres(i), '17/11/2026');
      expect(formaterHeure(heureParis(i)), '19h00');
    });
    test('été', () {
      expect(formaterDateEtHeure(DateTime.utc(2027, 7, 6, 17)), 'mardi 6 juillet 2027 à 19h00');
    });
    test('jour de Paris affiché, même quand le jour UTC diffère', () {
      // Événement le 16/11 à 00:30 à Paris = 15/11 23:30 UTC.
      expect(formaterHorodatage(DateTime.utc(2026, 11, 15, 23, 30)), '16 nov. · 00:30');
    });
  });

  group('couverture des données de fuseau', () {
    test('au moins 3 ans de marge (sinon : mettre à jour le package timezone)', () {
      final marge = DateTime.now().toUtc().add(const Duration(days: 3 * 365));
      expect(finCouvertureParis.isAfter(marge), isTrue,
          reason: 'données Europe/Paris jusqu’au $finCouvertureParis seulement');
    });
    test('au-delà : refus explicite, jamais un décalage faux', () {
      expect(() => paris(2031, 7, 8, 19), throwsA(isA<HorsCouvertureFuseau>()));
      expect(() => enParis(DateTime.utc(2031, 7, 8, 17)), throwsA(isA<HorsCouvertureFuseau>()));
    });
  });

  // Référence PostgreSQL (tzdata du serveur) : fichier produit par
  // qa/run_metier.sh, une ligne « AAAA-MM-JJ HH:MM<TAB>instant UTC » par
  // créneau et par jour. Ignoré hors du banc QA.
  final reference = Platform.environment['SWEND_TZ_REFERENCE'];
  test('identique à PostgreSQL (Europe/Paris) pour chaque créneau de chaque jour', () {
    final lignes = File(reference!).readAsLinesSync().where((l) => l.isNotEmpty).toList();
    expect(lignes.length, greaterThan(10000));
    final ecarts = <String>[];
    for (final l in lignes) {
      final c = l.split('\t');
      final m = DateTime.parse(c[0]);
      final calcule = paris(m.year, m.month, m.day, m.hour, m.minute);
      if (calcule != DateTime.parse(c[1])) ecarts.add('$l → ${isoInstant(calcule)}');
      if (enParis(calcule).hour != m.hour || jourParis(calcule) != DateTime(m.year, m.month, m.day)) {
        ecarts.add('$l (retour)');
      }
    }
    expect(ecarts, isEmpty, reason: ecarts.take(5).join('\n'));
  }, skip: (reference ?? '').isEmpty ? 'hors banc QA (SWEND_TZ_REFERENCE absent)' : false);
}
