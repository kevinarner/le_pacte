import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/models/annulation_swend.dart';
import 'package:le_pacte/models/cote_pacte.dart';
import 'package:le_pacte/models/evenement_fil.dart';
import 'package:le_pacte/models/gel_swend.dart';
import 'package:le_pacte/models/pacte.dart';
import 'package:le_pacte/models/remplacant.dart';
import 'package:le_pacte/models/statut_pacte.dart';
import 'package:le_pacte/models/type_repas.dart';
import 'package:le_pacte/utils/date_fr.dart';

/// Gel à H (D-023a) : ce que l'app masque à l'heure du Swend. La base reste
/// seule juge (tests SQL `98_gel_a_h.sql`).
void main() {
  final h = DateTime.utc(2031, 10, 13, 18);
  Pacte swend(StatutPacte statut, DateTime? date) => Pacte(
    id: 'p',
    type: TypeRepas.diner,
    datesProposees: const [],
    restaurantsProposes: const [],
    statut: statut,
    dateRetenue: date,
    initiateur: CotePacte(
      idTitulaire: 'eliot',
      nomTitulaire: 'Eliot Martin',
      listeRemplacants: const [],
    ),
    destinataire: CotePacte(
      idTitulaire: 'david',
      nomTitulaire: 'David',
      listeRemplacants: const [],
    ),
  );

  group('Gel à H (D-023a)', () {
    test('passé exactement à H, pas une seconde avant', () {
      final p = swend(StatutPacte.confirme, h);
      expect(estPasse(p, h.subtract(const Duration(seconds: 1))), isFalse);
      expect(estPasse(p, h), isTrue);
      expect(estPasse(p, h.add(const Duration(minutes: 1))), isTrue);
      expect(estPasse(swend(StatutPacte.confirme, null), h), isFalse);
    });

    test('imprévu ouvert seulement pour un Swend scellé, avant H', () {
      final avant = h.subtract(const Duration(minutes: 1));
      expect(imprevuOuvert(swend(StatutPacte.confirme, h), avant), isTrue);
      expect(imprevuOuvert(swend(StatutPacte.confirme, h), h), isFalse);
      expect(imprevuOuvert(swend(StatutPacte.annule, h), avant), isFalse);
      expect(
        imprevuOuvert(swend(StatutPacte.annuleDoubleAbsence, h), avant),
        isFalse,
      );
    });

    test('conversation en lecture seule après H et dès l\'annulation', () {
      final avant = h.subtract(const Duration(hours: 2));
      expect(
        conversationEnLectureSeule(swend(StatutPacte.confirme, h), avant),
        isFalse,
      );
      expect(
        conversationEnLectureSeule(swend(StatutPacte.confirme, h), h),
        isTrue,
      );
      expect(
        conversationEnLectureSeule(swend(StatutPacte.annule, h), avant),
        isTrue,
      );
    });

    test('annulation impossible après H (règle D-022 conservée)', () {
      expect(
        peutAnnulerSwend(
          swend(StatutPacte.confirme, h),
          estTitulaire: true,
          maintenant: h,
        ),
        isFalse,
      );
    });

    test('Swend passé : rejoint « Passés et annulés », statut inchangé', () {
      final p = swend(StatutPacte.confirme, h);
      expect(estPasseOuAnnule(p, h), isTrue);
      expect(p.statut, StatutPacte.confirme);
    });

    test('événement de fin : même texte pour les deux lecteurs', () {
      final e = EvenementFil(
        id: 'e',
        remplacantId: 'r',
        code: 'swend_commence',
        createdAt: h,
      );
      const attendu =
          'Le Swend a commencé.\nCette conversation est désormais terminée.';
      expect(e.texte(vuParTiers: true, autre: 'Eliot'), attendu);
      expect(e.texte(vuParTiers: false, autre: 'Kevin'), attendu);
    });

    test('événement de fin : ne rend jamais la conversation non lue', () {
      final e = EvenementFil(
        id: 'e',
        remplacantId: 'r',
        code: 'swend_commence',
        createdAt: h,
      );
      expect(e.concerneLecteur(vuParTiers: true), isFalse);
      expect(e.concerneLecteur(vuParTiers: false), isFalse);
    });

    test('relecture : seulement les conversations actives, comptes d\'abord', () {
      final fiches = [
        Remplacant(id: 'tom', prenom: 'Tom'),
        Remplacant(id: 'kevin', prenom: 'Kevin', profilId: 'k'),
        Remplacant(id: 'thomas', prenom: 'Thomas', profilId: 't'),
        Remplacant(prenom: 'Brouillon'),
      ];
      final aRelire = filsARelire(fiches, {'tom', 'kevin'});
      expect(aRelire.map((r) => r.prenom), ['Kevin', 'Tom']);
      expect(filsARelire(fiches, {}), isEmpty);
    });

    test('message propre si la base refuse après H', () {
      expect(messageSwendPasse, contains('L’heure du Swend est passée'));
    });
  });

  group('Échéance H-3 (D-027, 20/10)', () {
    final p = swend(StatutPacte.confirme, h);
    final h3 = h.subtract(const Duration(hours: 3));
    test('échéance à H-3 exactement, incluse', () {
      expect(echeanceH3(p), h3);
      final juste = h3.subtract(const Duration(seconds: 1));
      expect(echeanceH3Atteinte(p, juste), isFalse);
      expect(echeanceH3Atteinte(p, h3), isTrue);
      expect(echeanceH3Atteinte(p, h3.add(const Duration(minutes: 1))), isTrue);
      final sansDate = swend(StatutPacte.confirme, null);
      expect(echeanceH3(sansDate), isNull);
      expect(echeanceH3Atteinte(sansDate, h), isFalse);
    });
    test('entre H-3 et H : annulation encore possible, recherche close', () {
      final entre = h.subtract(const Duration(hours: 1));
      expect(imprevuOuvert(p, entre), isTrue);
      expect(echeanceH3Atteinte(p, entre), isTrue);
    });
    test('Swend du 17 novembre à 19h00 (Paris) : H-3 = 16h00', () {
      // 19h00 à Paris en novembre (UTC+1) = 18h00 UTC.
      final s = swend(StatutPacte.confirme, DateTime.utc(2026, 11, 17, 18));
      expect(echeanceH3(s), DateTime.utc(2026, 11, 17, 15));
      expect(formaterJourEtHeure(echeanceH3(s)!), 'mardi 17 novembre à 16h00');
    });
    test('message propre si la base refuse dès H-3', () {
      expect(messageEcheanceH3, contains('à partir de 3 heures avant le Swend'));
    });
  });
}
