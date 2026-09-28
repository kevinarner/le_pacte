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
import 'package:le_pacte/models/annulation_swend.dart';
import 'package:le_pacte/models/destination_rappel.dart';
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

  group('Clic sur un rappel (D-021) : destination calculée par la base', () {
    test('titulaire qui cherche encore quelqu\'un → Un imprévu ?', () {
      expect(
        destinationRappelDepuis('imprevu'),
        DestinationRappel.imprevu,
      );
    });
    test('participant, titulaire remplacé, remplaçant accepté → fiche', () {
      expect(
        destinationRappelDepuis('fiche'),
        DestinationRappel.fiche,
      );
    });
    test('plus d\'accès (ex. désisté) ou réponse inconnue → rien', () {
      expect(destinationRappelDepuis(null), isNull);
      expect(destinationRappelDepuis('autre'), isNull);
    });
    test('web : le lien ?rappel=<pacte_id> désigne le Swend', () {
      final lien = Uri.parse('https://kevinarner.github.io/le_pacte/?rappel=abc-123#/');
      expect(pacteDuLienRappel(lien), 'abc-123');
      expect(pacteDuLienRappel(Uri.parse('https://kevinarner.github.io/le_pacte/')), isNull);
      expect(pacteDuLienRappel(Uri.parse('https://kevinarner.github.io/le_pacte/?rappel=')), isNull);
    });
    test('web : l\'adresse est nettoyée du rappel, le reste est conservé', () {
      expect(
        adresseSansRappel(Uri.parse('https://kevinarner.github.io/le_pacte/?rappel=abc-123#/')),
        '/le_pacte/#/',
      );
      expect(
        adresseSansRappel(Uri.parse('http://127.0.0.1:8080/?x=1&rappel=abc')),
        '/?x=1',
      );
    });
  });

  group('Annulation manuelle d\'un Swend (D-022)', () {
    CotePacte cote(List<Remplacant> fiches) => CotePacte(
      idTitulaire: 'eliot',
      nomTitulaire: 'Eliot Martin',
      listeRemplacants: fiches,
    );
    Pacte swend(StatutPacte statut, DateTime? date) => Pacte(
      id: 'p',
      type: TypeRepas.diner,
      datesProposees: const [],
      restaurantsProposes: const [],
      statut: statut,
      dateRetenue: date,
      initiateur: cote(const []),
      destinataire: CotePacte(
        idTitulaire: 'david',
        nomTitulaire: 'David',
        listeRemplacants: const [],
      ),
    );
    test('aucun imprévu lancé : proposer d\'abord un remplaçant', () {
      final c = ConfirmationAnnulation.pour(
        cote([Remplacant(prenom: 'Kevin')]),
      );
      expect(c.cas, CasAnnulation.normal);
      expect(c.titre, 'Annuler ce Swend ?');
      expect(c.corps, 'Cette action mettra fin au Swend pour vous deux.');
      expect(c.actionGarder, 'Ne pas annuler');
      expect(c.actionAnnuler, 'Annuler le Swend');
      expect(AvantAnnulation.titre, 'Vous ne pouvez plus être là ?');
      expect(AvantAnnulation.actionTrouver, 'Trouver quelqu’un pour me remplacer');
      expect(AvantAnnulation.actionAnnuler, 'Annuler malgré tout');
    });
    test('demande en attente : « Continuer à chercher », demandes annulées', () {
      final c = ConfirmationAnnulation.pour(
        cote([
          Remplacant(prenom: 'Kevin', demandeStatut: DemandeStatut.envoyee),
          Remplacant(prenom: 'Tom', demandeStatut: DemandeStatut.refusee),
        ]),
      );
      expect(c.cas, CasAnnulation.enRecherche);
      expect(
        c.corps,
        'Les demandes de remplacement en cours seront annulées et le Swend prendra fin pour vous deux.',
      );
      expect(c.actionGarder, 'Continuer à chercher');
    });
    test('seulement des refus / désistements : déjà cherché', () {
      for (final statut in [DemandeStatut.refusee, DemandeStatut.desistee]) {
        final c = ConfirmationAnnulation.pour(
          cote([Remplacant(prenom: 'Tom', demandeStatut: statut)]),
        );
        expect(c.cas, CasAnnulation.enRecherche);
        expect(
          c.corps,
          'Vous avez déjà cherché quelqu’un pour vous remplacer. Si vous annulez, le Swend prendra fin pour vous deux.',
        );
      }
    });
    test('demande close ou annulée seulement : cas normal', () {
      final c = ConfirmationAnnulation.pour(
        cote([Remplacant(prenom: 'Tom', demandeStatut: DemandeStatut.cloturee)]),
      );
      expect(c.cas, CasAnnulation.normal);
    });
    test('quelqu\'un a accepté : son prénom, fin pour tout le monde', () {
      final c = ConfirmationAnnulation.pour(
        cote([
          Remplacant(prenom: 'Sylvain', demandeStatut: DemandeStatut.cloturee),
          Remplacant(
            prenom: 'Kevin ',
            selectionne: true,
            demandeStatut: DemandeStatut.acceptee,
          ),
        ]),
      );
      expect(c.cas, CasAnnulation.remplace);
      expect(
        c.corps,
        'Kevin a accepté de prendre votre place.\nSi vous annulez, le Swend prendra fin pour tout le monde.',
      );
      expect(c.actionGarder, 'Ne pas annuler');
    });
    test('annulable jusqu\'à l\'heure du rendez-vous, par un titulaire', () {
      final maintenant = DateTime(2031, 10, 13, 19, 59);
      final rdv = DateTime(2031, 10, 13, 20);
      expect(
        peutAnnulerSwend(swend(StatutPacte.confirme, rdv), estTitulaire: true, maintenant: maintenant),
        isTrue,
      );
      expect(
        peutAnnulerSwend(swend(StatutPacte.confirme, rdv), estTitulaire: true, maintenant: rdv),
        isFalse,
      );
      expect(
        peutAnnulerSwend(swend(StatutPacte.confirme, rdv), estTitulaire: false, maintenant: maintenant),
        isFalse,
      );
      expect(
        peutAnnulerSwend(swend(StatutPacte.annule, rdv), estTitulaire: true, maintenant: maintenant),
        isFalse,
      );
    });
    test('Mes Swends : annulés et passés à part, jamais présentés comme actifs', () {
      final maintenant = DateTime(2031, 10, 1);
      final futur = DateTime(2031, 10, 13, 20);
      final passe = DateTime(2031, 9, 1, 20);
      expect(estPasseOuAnnule(swend(StatutPacte.confirme, futur), maintenant), isFalse);
      expect(estPasseOuAnnule(swend(StatutPacte.enAttenteReponse, null), maintenant), isFalse);
      expect(estPasseOuAnnule(swend(StatutPacte.annule, futur), maintenant), isTrue);
      expect(estPasseOuAnnule(swend(StatutPacte.annuleDoubleAbsence, futur), maintenant), isTrue);
      expect(estPasseOuAnnule(swend(StatutPacte.confirme, passe), maintenant), isTrue);
      expect(StatutPacte.annule.libelle, 'Annulé');
    });
    test('refus de la base : message compréhensible', () {
      expect(
        messageErreurAnnulation(Exception('... swend_passe ...')),
        'L’heure du rendez-vous est passée : ce Swend ne peut plus être annulé.',
      );
      expect(messageErreurAnnulation(Exception('swend_inactif')), 'Ce Swend n’est plus actif.');
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
