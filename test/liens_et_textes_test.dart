import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:le_pacte/utils/heure_paris.dart';
import 'package:le_pacte/models/cote_pacte.dart';
import 'package:le_pacte/models/pacte.dart';
import 'package:le_pacte/models/remplacant.dart';
import 'package:le_pacte/models/restaurant.dart';
import 'package:le_pacte/models/statut_pacte.dart';
import 'package:le_pacte/models/type_repas.dart';
import 'package:le_pacte/utils/telephone.dart';
import 'package:le_pacte/utils/textes_invitation.dart';
import 'package:le_pacte/widgets/envoi_invitation.dart';

void main() {
  group('Liens Messages / WhatsApp', () {
    const texte = "Hello Tom, j'ai un imprévu ?\nÇa te dit & merci";

    test('Messages : sms: vers le numéro E.164, texte encodé', () {
      final e164 = normaliserTelephone('07 11 22 33 44')!;
      final lien = lienMessages(e164, texte);
      expect(lien.scheme, 'sms');
      expect(lien.toString(), startsWith('sms:+33711223344?body='));
      expect(Uri.decodeComponent(lien.toString().split('body=')[1]), texte);
    });

    test('WhatsApp : wa.me sans le "+", texte encodé', () {
      final lien = lienWhatsApp('+33711223344', texte);
      expect(lien.toString(), startsWith('https://wa.me/33711223344?text='));
      expect(lien.queryParameters['text'], texte);
    });

    test('même texte quel que soit le canal', () {
      final sms = lienMessages('+33711223344', texte);
      final wa = lienWhatsApp('+33711223344', texte);
      expect(
        Uri.decodeComponent(sms.toString().split('body=')[1]),
        wa.queryParameters['text'],
      );
    });

    test('outre-mer et étranger : bons indicatifs', () {
      expect(
        lienWhatsApp(normaliserTelephone('0692 12 34 56')!, 'x').toString(),
        startsWith('https://wa.me/262692123456'),
      );
      expect(
        lienMessages(normaliserTelephone('+44 7911 123456')!, 'x').toString(),
        startsWith('sms:+447911123456'),
      );
    });
  });

  group('Textes envoyés', () {
    test('invitation à un Swend', () {
      final t = texteInvitationSwend(' David ');
      expect(
        t,
        startsWith("Hello David, je t'invite à faire un Swend avec moi !"),
      );
      expect(t, endsWith('https://kevinarner.github.io/le_pacte/'));
      expect(texteInvitationSwend(''), startsWith("Hello, je t'invite"));
    });

    test('invitation d\'une personne de confiance', () {
      final t = texteInvitationPersonneDeConfiance('Tom', 'David Schlang');
      expect(t, startsWith("Hello Tom, j'ai proposé un Swend à David"));
      expect(t, contains("compter sur toi en cas d'imprévu"));
    });

    test(
      'message d\'urgence : contexte complet + consigne de création de compte',
      () {
        final eliot = CotePacte(
          idTitulaire: 'e',
          nomTitulaire: 'Eliot Martin',
          listeRemplacants: [],
        );
        final david = CotePacte(
          idTitulaire: 'd',
          nomTitulaire: 'David Schlang',
          listeRemplacants: [],
        );
        final pacte = Pacte(
          id: 'p',
          type: TypeRepas.diner,
          datesProposees: const [],
          dateRetenue: instantParis(DateTime(2026, 10, 27), const TimeOfDay(hour: 19, minute: 30)),
          restaurantsProposes: const [],
          initiateur: eliot,
          destinataire: david,
          statut: StatutPacte.confirme,
        )..restaurantRetenu = Restaurant(nom: 'Au père Lapin', lien: '');
        final t = messageUrgence(pacte, Remplacant(prenom: 'Tom'), david);
        expect(
          t,
          startsWith(
            "Hello Tom, j'ai un dîner prévu le 27 octobre à 19h30 avec David, au restaurant Au père Lapin",
          ),
        );
        expect(
          t,
          contains("David ne saura pas que c'est toi qui me remplaces."),
        );
        expect(
          t,
          contains(
            'Pour retrouver cette demande dans Swend, crée ton compte avec ce numéro de téléphone.',
          ),
        );
      },
    );
  });
}
