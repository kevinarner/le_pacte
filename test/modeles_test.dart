import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/models/cote_pacte.dart';
import 'package:le_pacte/models/demande_statut.dart';
import 'package:le_pacte/models/evenement_fil.dart';
import 'package:le_pacte/models/pacte.dart';
import 'package:le_pacte/models/perspective_pacte.dart';
import 'package:le_pacte/models/remplacant.dart';
import 'package:le_pacte/models/statut_pacte.dart';
import 'package:le_pacte/models/type_repas.dart';
import 'package:le_pacte/screens/detail_pacte/bloc_choix_date.dart';
import 'package:le_pacte/utils/date_fr.dart';
import 'package:le_pacte/widgets/action_disponibilite.dart';

EvenementFil _ev(String code) => EvenementFil(
  id: 'x',
  remplacantId: 'r',
  code: code,
  createdAt: DateTime(2026, 11, 10, 9, 42),
);

void main() {
  group('Événements du fil : formulation selon qui lit', () {
    const attendus = {
      'demande_envoyee': [
        "Eliot t'a demandé de prendre sa place.",
        'Tu as demandé à Kevin de prendre ta place.',
      ],
      'demande_annulee': [
        'Eliot a annulé sa demande.',
        'Tu as annulé ta demande à Kevin.',
      ],
      'demande_refusee': [
        "Tu as refusé de prendre la place d'Eliot.",
        'Kevin a refusé de prendre ta place.',
      ],
      'demande_acceptee': [
        "Tu as accepté de prendre la place d'Eliot.",
        'Kevin a accepté de prendre ta place.',
      ],
      'desistement': [
        "Tu ne prends plus la place d'Eliot.",
        'Kevin ne peut finalement plus prendre ta place.',
      ],
      'demande_cloturee': [
        "La demande n'est plus d'actualité.",
        "La demande à Kevin n'est plus d'actualité.",
      ],
      'indisponibilite_signalee': [
        'Tu as indiqué à Eliot que tu ne seras pas disponible.',
        "Kevin ne sera pas disponible en cas d'imprévu.",
      ],
      'disponibilite_retablie': [
        'Tu as indiqué à Eliot que tu es finalement disponible.',
        "Kevin est de nouveau disponible en cas d'imprévu.",
      ],
    };
    attendus.forEach((code, textes) {
      test(code, () {
        expect(_ev(code).texte(vuParTiers: true, autre: 'Eliot'), textes[0]);
        expect(_ev(code).texte(vuParTiers: false, autre: 'Kevin'), textes[1]);
      });
    });
    test('clôture vue par le tiers : ne nomme personne', () {
      expect(
        _ev('demande_cloturee').texte(vuParTiers: true, autre: 'Eliot'),
        isNot(contains('Eliot')),
      );
    });
    test('horodatage "10 nov. · 09:42"', () {
      expect(
        formaterHorodatage(DateTime(2026, 11, 10, 9, 42)),
        '10 nov. · 09:42',
      );
    });
  });

  group('Événements qui rendent une conversation non lue (D-015)', () {
    test('titulaire : les actions de la personne de confiance', () {
      for (final code in [
        'demande_refusee',
        'demande_acceptee',
        'desistement',
        'indisponibilite_signalee',
        'disponibilite_retablie',
      ]) {
        expect(
          _ev(code).concerneLecteur(vuParTiers: false),
          isTrue,
          reason: code,
        );
      }
    });
    test('titulaire : pas ses propres actions ni la clôture automatique', () {
      for (final code in [
        'demande_envoyee',
        'demande_annulee',
        'demande_cloturee',
      ]) {
        expect(
          _ev(code).concerneLecteur(vuParTiers: false),
          isFalse,
          reason: code,
        );
      }
    });
    test(
      'personne de confiance : seulement l\'annulation par le titulaire',
      () {
        expect(
          _ev('demande_annulee').concerneLecteur(vuParTiers: true),
          isTrue,
        );
        for (final code in [
          'demande_envoyee', // a déjà sa carte "Une demande t'attend"
          'demande_cloturee', // déjà notifiée, pas une action du titulaire
          'demande_refusee',
          'demande_acceptee',
          'desistement',
          'indisponibilite_signalee',
          'disponibilite_retablie',
        ]) {
          expect(
            _ev(code).concerneLecteur(vuParTiers: true),
            isFalse,
            reason: code,
          );
        }
      },
    );
  });

  group('Indisponibilité spontanée (D-008)', () {
    Remplacant fiche({
      DemandeStatut? statut,
      bool sel = false,
      bool indispo = false,
    }) => Remplacant(
      id: 'r',
      prenom: 'Kevin',
      nom: 'A',
      telephone: '0600000003',
      profilId: 'k',
      demandeStatut: statut,
      selectionne: sel,
      indisponibleSpontanement: indispo,
    );
    test(
      'simplement prévue : peut se déclarer indisponible, reste disponible',
      () {
        final r = fiche();
        expect(r.peutSeDeclarerIndisponible, isTrue);
        expect(r.estIndisponible, isFalse);
        expect(ActionDisponibilite.concerne(r), isTrue);
      },
    );
    test(
      'indisponible spontanément : indisponible côté titulaire, réversible',
      () {
        final r = fiche(indispo: true);
        expect(r.estIndisponible, isTrue);
        expect(r.demandeStatut, isNull);
        expect(r.peutSeDeclarerIndisponible, isFalse);
        expect(
          ActionDisponibilite.concerne(r),
          isTrue,
        ); // "Je suis finalement disponible"
      },
    );
    test(
      'demande en cours, place prise, refus, désistement : action absente',
      () {
        for (final r in [
          fiche(statut: DemandeStatut.envoyee),
          fiche(statut: DemandeStatut.acceptee, sel: true),
          fiche(statut: DemandeStatut.refusee),
          fiche(statut: DemandeStatut.desistee),
          fiche(statut: DemandeStatut.cloturee),
        ]) {
          expect(
            ActionDisponibilite.concerne(r),
            isFalse,
            reason: '${r.demandeStatut}',
          );
        }
      },
    );
    test('refus et désistement restent indisponibles sans drapeau', () {
      expect(fiche(statut: DemandeStatut.refusee).estIndisponible, isTrue);
      expect(fiche(statut: DemandeStatut.desistee).estIndisponible, isTrue);
    });
    test('le drapeau ne touche pas le cycle d\'une demande', () {
      expect(fiche(indispo: true).demandeStatut.estIndisponible, isFalse);
    });
  });

  group('Négociation de date (D-011) : 2 contre-propositions au total', () {
    test('proposition initiale : contre-proposition n°1 possible', () {
      expect(peutEncoreContreProposer(0), isTrue);
    });
    test('après la n°1 (quel que soit son auteur) : n°2 possible', () {
      expect(peutEncoreContreProposer(1), isTrue);
    });
    test('après la n°2 : plus aucune contre-proposition', () {
      expect(peutEncoreContreProposer(2), isFalse);
      expect(peutEncoreContreProposer(3), isFalse);
    });
  });

  group('Personnes de confiance', () {
    test('comptes Swend d\'abord, ordre conservé dans chaque groupe', () {
      final l = [
        Remplacant(prenom: 't'),
        Remplacant(prenom: 'Kevin', profilId: 'k'),
        Remplacant(prenom: 'Zoé'),
        Remplacant(prenom: 'Sylvain', profilId: 's'),
      ];
      expect(Remplacant.comptesDAbord(l).map((r) => r.prenom), [
        'Kevin',
        'Sylvain',
        't',
        'Zoé',
      ]);
    });
    test('nom complet sans espaces parasites', () {
      expect(
        Remplacant(prenom: 'Kevin ', nom: ' Arner').nomComplet,
        'Kevin Arner',
      );
    });
    test('indisponibles : refus, clôture, désistement', () {
      expect(DemandeStatut.refusee.estIndisponible, isTrue);
      expect(DemandeStatut.cloturee.estIndisponible, isTrue);
      expect(DemandeStatut.desistee.estIndisponible, isTrue);
      expect(DemandeStatut.envoyee.estIndisponible, isFalse);
    });
  });

  group('Rôle sur un Swend (PerspectivePacte)', () {
    Pacte pacte({
      List<Remplacant> init = const [],
      List<Remplacant> dest = const [],
    }) => Pacte(
      id: 'p',
      type: TypeRepas.diner,
      datesProposees: const [],
      restaurantsProposes: const [],
      statut: StatutPacte.confirme,
      initiateur: CotePacte(
        idTitulaire: 'eliot',
        nomTitulaire: 'Eliot Martin',
        listeRemplacants: init,
      ),
      destinataire: CotePacte(
        idTitulaire: 'david',
        nomTitulaire: 'David Schlang',
        listeRemplacants: dest,
      ),
    );
    test('titulaires', () {
      expect(PerspectivePacte.de(pacte(), 'eliot')!.jeSuisInitiateur, isTrue);
      expect(
        PerspectivePacte.de(pacte(), 'david')!.role,
        RolePacte.destinataire,
      );
    });
    test('tiers : sa fiche, le titulaire et l\'autre participant', () {
      final v = PerspectivePacte.de(
        pacte(
          init: [Remplacant(id: 'r', profilId: 'kevin')],
        ),
        'kevin',
      )!;
      expect(v.estTitulaire, isFalse);
      expect(v.coteTitulaire!.nomTitulaire, 'Eliot Martin');
      expect(v.coteAutreParticipant!.nomTitulaire, 'David Schlang');
    });
    test('prévu des deux côtés : la place acceptée l\'emporte', () {
      final v = PerspectivePacte.de(
        pacte(
          init: [
            Remplacant(
              id: 'a',
              profilId: 'kevin',
              demandeStatut: DemandeStatut.cloturee,
            ),
          ],
          dest: [
            Remplacant(
              id: 'b',
              profilId: 'kevin',
              selectionne: true,
              demandeStatut: DemandeStatut.acceptee,
            ),
          ],
        ),
        'kevin',
      )!;
      expect(v.maFiche!.id, 'b');
      expect(v.coteTitulaire!.nomTitulaire, 'David Schlang');
    });
    test('sans lien avec le Swend : aucun rôle', () {
      expect(PerspectivePacte.de(pacte(), 'inconnu'), isNull);
    });
  });
}
