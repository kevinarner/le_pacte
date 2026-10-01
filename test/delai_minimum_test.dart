import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/models/delai_minimum.dart';
import 'package:le_pacte/services/pacte_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:le_pacte/widgets/dates_form.dart';

/// Délai minimum avant un Swend (D-025) : ce que l'app en fait (calendrier,
/// message). La base reste seule juge (tests SQL `99c_delai_minimum.sql`).
void main() {
  test('date_minimale de la base → jour, ou null', () {
    expect(dateMinimaleDepuis('2026-10-16'), DateTime(2026, 10, 16));
    expect(dateMinimaleDepuis(null), isNull);
    expect(dateMinimaleDepuis(''), isNull);
    expect(dateMinimaleDepuis('pas une date'), isNull);
    expect(dateMinimaleDepuis(42), isNull);
  });

  test('premier jour sélectionnable : la date minimale, sinon aujourd’hui', () {
    final maintenant = DateTime(2026, 10, 1, 23, 30);
    expect(premierJourSelectionnable(maintenant, DateTime(2026, 10, 16)),
        DateTime(2026, 10, 16));
    // Exempté (fondateur) ou Swend antérieur à la règle : aujourd'hui.
    expect(premierJourSelectionnable(maintenant, null), DateTime(2026, 10, 1));
    // Date minimale déjà passée (négociation ancienne) : aujourd'hui.
    expect(premierJourSelectionnable(maintenant, DateTime(2026, 9, 20)),
        DateTime(2026, 10, 1));
  });

  test('J+14 refusé, J+15 accepté, à toute heure', () {
    final min = DateTime(2026, 10, 16);
    expect(respecteDateMinimale(DateTime(2026, 10, 15, 23, 59), min), isFalse);
    expect(respecteDateMinimale(DateTime(2026, 10, 16, 0, 0), min), isTrue);
    expect(respecteDateMinimale(DateTime(2026, 10, 16, 21, 0), min), isTrue);
    expect(respecteDateMinimale(DateTime(2026, 11, 1), min), isTrue);
    expect(respecteDateMinimale(DateTime(2026, 10, 2), null), isTrue);
  });

  test('message de refus', () {
    expect(
      messageDateTropProche(DateTime(2026, 10, 16)),
      'Choisissez une date au moins 15 jours à l’avance. '
      'Première date possible : 16 octobre.',
    );
  });

  test('refus de la base : code et première date possible (détail)', () {
    const refus = PostgrestException(message: 'date_trop_proche', code: 'P0001', details: '2026-10-16');
    expect(PacteRepository.codeErreurMetier(refus), 'date_trop_proche');
    expect(PacteRepository.dateMinimaleDeErreur(refus), DateTime(2026, 10, 16));
    expect(PacteRepository.dateMinimaleDeErreur(const PostgrestException(message: 'autre')), isNull);
    expect(PacteRepository.dateMinimaleDeErreur(Exception('x')), isNull);
  });

  // Le calendrier ouvert par « Ajouter une date » commence à la date minimale.
  Future<DatePickerDialog> calendrier(WidgetTester tester, DateTime? min) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('fr', 'FR')],
      home: Scaffold(
        body: DatesForm(
          dates: [],
          onChanged: () {},
          creneaux: const [TimeOfDay(hour: 19, minute: 30)],
          dateMinimale: min,
        ),
      ),
    ));
    await tester.tap(find.text('Ajouter une date'));
    await tester.pumpAndSettle();
    return tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
  }

  DateTime jour(DateTime d) => DateTime(d.year, d.month, d.day);

  testWidgets('calendrier : rien avant la date minimale', (tester) async {
    final min = jour(DateTime.now().add(const Duration(days: 15)));
    final dialogue = await calendrier(tester, min);
    expect(jour(dialogue.firstDate), min);
    expect(dialogue.initialDate!.isBefore(min), isFalse);
  });

  testWidgets('calendrier sans date minimale : à partir d’aujourd’hui', (tester) async {
    final dialogue = await calendrier(tester, null);
    expect(jour(dialogue.firstDate), jour(DateTime.now()));
  });

  testWidgets('date minimale plus tardive que le départ (+60 j) : départ recalé', (tester) async {
    final min = jour(DateTime.now().add(const Duration(days: 90)));
    final dialogue = await calendrier(tester, min);
    expect(jour(dialogue.firstDate), min);
    expect(dialogue.initialDate!.isBefore(min), isFalse);
  });
}
