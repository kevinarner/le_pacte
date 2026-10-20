import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/models/demande_statut.dart';
import 'package:le_pacte/models/imprevu.dart';
import 'package:le_pacte/models/remplacant.dart';

/// « Un imprévu ? » (D-027, lot 3) : situation de mon côté, phases, actions
/// proposées et textes, indépendamment de l'écran.
void main() {
  var n = 0;
  Remplacant fiche(
    String prenom, {
    DemandeStatut? statut,
    bool sel = false,
    bool compte = true,
    bool indispo = false,
    bool renvoyer = false,
  }) => Remplacant(
    id: 'f${n++}',
    prenom: prenom,
    nom: 'X',
    telephone: '0600000000',
    profilId: compte ? 'p$prenom' : null,
    demandeStatut: statut,
    selectionne: sel,
    indisponibleSpontanement: indispo,
    messageARenvoyer: renvoyer,
  );

  group('État de mon côté (destination_rappel)', () {
    test(
      'une place prise : remplacé, quelle que soit la réponse de la base',
      () {
        final f = [fiche('Kevin', statut: DemandeStatut.acceptee, sel: true)];
        expect(
          etatCoteDepuis(
            destinationRappel: 'fiche',
            baseARepondu: true,
            fiches: f,
          ),
          EtatCote.remplace,
        );
      },
    );
    test(
      '« imprevu » ⇔ imprévu déclaré ; sinon normal (même avec des refus)',
      () {
        final f = [fiche('Tom', statut: DemandeStatut.refusee)];
        expect(
          etatCoteDepuis(
            destinationRappel: 'imprevu',
            baseARepondu: true,
            fiches: f,
          ),
          EtatCote.cherche,
        );
        // Après « Je peux finalement venir », les refus restent : seule la
        // base sait que l'imprévu est terminé.
        expect(
          etatCoteDepuis(
            destinationRappel: 'fiche',
            baseARepondu: true,
            fiches: f,
          ),
          EtatCote.normal,
        );
      },
    );
    test('repli sans réponse de la base : d\'après les fiches', () {
      expect(
        etatCoteDepuis(
          destinationRappel: null,
          baseARepondu: false,
          fiches: [fiche('Kevin', statut: DemandeStatut.envoyee)],
        ),
        EtatCote.cherche,
      );
      expect(
        etatCoteDepuis(
          destinationRappel: null,
          baseARepondu: false,
          fiches: [fiche('Kevin')],
        ),
        EtatCote.normal,
      );
    });
  });

  group('Phases et actions', () {
    test('pas d\'imprévu : choisir parmi les personnes sollicitables', () {
      final s = SituationImprevu(
        etat: EtatCote.normal,
        fiches: [
          fiche('Kevin'),
          fiche('Tom', compte: false),
          fiche('Sylvain', statut: DemandeStatut.refusee),
          fiche('Zoé', indispo: true),
        ],
      );
      expect(s.phase, PhaseImprevu.choix);
      expect(s.sollicitables.map((r) => r.prenom), ['Kevin', 'Tom']);
      expect(s.entete, (
        TextesImprevu.titreChoix,
        TextesImprevu.sousTitreChoix,
      ));
      expect(s.peutRevenir, isFalse);
      expect(s.dernierRecours, isFalse);
    });
    test('personne à solliciter : dernier recours possible', () {
      final vide = SituationImprevu(etat: EtatCote.normal, fiches: const []);
      expect(vide.dernierRecours, isTrue);
      expect(vide.entete.$2, TextesImprevu.personnePrevue);
      final indispo = SituationImprevu(
        etat: EtatCote.normal,
        fiches: [fiche('Sylvain', statut: DemandeStatut.refusee)],
      );
      expect(indispo.dernierRecours, isTrue);
      expect(indispo.entete.$2, TextesImprevu.personneDisponible);
    });
    test(
      'demandes en attente : « C\'est envoyé. », retour possible, pas de dernier recours',
      () {
        final s = SituationImprevu(
          etat: EtatCote.cherche,
          fiches: [
            fiche('Kevin', statut: DemandeStatut.envoyee),
            fiche('Sylvain', statut: DemandeStatut.refusee),
            fiche('Zoé'),
          ],
        );
        expect(s.phase, PhaseImprevu.attente);
        expect(s.entete, (
          'C’est envoyé.',
          'La première personne qui accepte prendra ta place.',
        ));
        expect(s.sollicitees.map((r) => r.prenom), ['Kevin', 'Sylvain']);
        expect(s.sollicitables.map((r) => r.prenom), ['Zoé']);
        expect(s.peutRevenir, isTrue);
        expect(s.dernierRecours, isFalse);
      },
    );
    test(
      'tout le monde a refusé : « Personne n\'a pu… », retour et dernier recours',
      () {
        final s = SituationImprevu(
          etat: EtatCote.cherche,
          fiches: [fiche('Kevin', statut: DemandeStatut.refusee)],
        );
        expect(s.phase, PhaseImprevu.personneNaPu);
        expect(s.entete, (
          'Personne n’a pu prendre ta place.',
          'Tu peux encore solliciter quelqu’un d’autre.',
        ));
        expect(s.peutRevenir, isTrue);
        expect(s.dernierRecours, isTrue);
      },
    );
    test('accepté : texte neutre, plus de retour ni d\'annulation', () {
      final s = SituationImprevu(
        etat: EtatCote.remplace,
        fiches: [
          fiche('Kevin', statut: DemandeStatut.acceptee, sel: true),
          fiche('Sylvain', statut: DemandeStatut.cloturee),
        ],
      );
      expect(s.phase, PhaseImprevu.accepte);
      expect(s.entete, (
        'Kevin a accepté.',
        'Kevin sera là à ta place le jour J.',
      ));
      expect(s.peutRevenir, isFalse);
      expect(s.dernierRecours, isFalse);
      expect(s.sollicitees.map((r) => r.prenom), ['Sylvain']);
    });
    test(
      'fiches non enregistrées ou incomplètes ignorées, comptes d\'abord',
      () {
        final s = SituationImprevu(
          etat: EtatCote.normal,
          fiches: [
            fiche('Tom', compte: false),
            Remplacant(prenom: 'Brouillon'),
            fiche('Kevin'),
          ],
        );
        expect(s.fiches.map((r) => r.prenom), ['Kevin', 'Tom']);
      },
    );
  });

  group('Désistement (D-027 point 7)', () {
    final kevin = fiche('Kevin', statut: DemandeStatut.desistee);
    final tom = fiche(
      'Tom',
      statut: DemandeStatut.envoyee,
      compte: false,
      renvoyer: true,
    );
    final t0 = DateTime.utc(2031, 10, 1, 12);
    test('dernier désistement non suivi d\'un nouvel envoi', () {
      expect(
        desistementRecent(
          [kevin, tom],
          desistements: {kevin.id!: t0},
          dernierEnvoi: t0.subtract(const Duration(hours: 1)),
        ),
        kevin,
      );
      expect(
        desistementRecent(
          [kevin, tom],
          desistements: {kevin.id!: t0},
          dernierEnvoi: t0.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
      expect(
        desistementRecent([kevin], desistements: const {}, dernierEnvoi: null),
        isNull,
      );
    });
    test('demandes réactivées : textes du titulaire', () {
      final s = SituationImprevu(
        etat: EtatCote.cherche,
        fiches: [kevin, tom],
        desistementRecent: kevin,
      );
      expect(s.phase, PhaseImprevu.attente);
      expect(s.entete, (
        'Kevin ne peut finalement plus venir.',
        'Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.',
      ));
    });
    test('rien à réactiver : « Tu peux solliciter quelqu\'un d\'autre. »', () {
      final s = SituationImprevu(
        etat: EtatCote.cherche,
        fiches: [kevin],
        desistementRecent: kevin,
      );
      expect(s.phase, PhaseImprevu.personneNaPu);
      expect(s.entete, (
        'Kevin ne peut finalement plus venir.',
        'Tu peux solliciter quelqu’un d’autre.',
      ));
    });
  });

  group('Textes', () {
    test('bouton adaptatif', () {
      expect(TextesImprevu.boutonEnvoi(const []), isNull);
      expect(TextesImprevu.boutonEnvoi([fiche('Kevin ')]), 'Demander à Kevin');
      expect(
        TextesImprevu.boutonEnvoi([fiche('Kevin'), fiche('Tom')]),
        'Envoyer 2 demandes',
      );
    });
    test('confirmations avant l\'envoi (une personne : formulation neutre)', () {
      expect(TextesImprevu.confirmationEnvoi([fiche('Kevin')]), (
        'Envoyer la demande à Kevin ?',
        'En acceptant, Kevin prendra ta place et tu ne pourras plus revenir en arrière.',
        'Envoyer la demande',
      ));
      expect(TextesImprevu.confirmationEnvoi([fiche('Kevin'), fiche('Tom')]), (
        'Envoyer la demande ?',
        'La première personne qui accepte prendra ta place.\n'
            'Une fois ta place prise, tu ne pourras plus revenir en arrière.',
        'Envoyer les demandes',
      ));
    });
    test('personne sans compte (textes validés le 20/10)', () {
      expect(TextesImprevu.sansCompte('Tom'), 'Tom n’a pas encore de compte Swend.');
      expect(
        TextesImprevu.messageAEnvoyer('Tom'),
        'Tom n’a pas encore de compte Swend : envoie-lui un message pour lui '
        'expliquer et lui permettre de répondre depuis l’app.',
      );
    });
    test('dernier recours et annulation : textes validés D-027', () {
      expect(TextesImprevu.titrePersonneDAutre, 'Tu n’as personne d’autre ?');
      expect(
        TextesImprevu.corpsPersonneDAutre,
        'Sans quelqu’un pour prendre ta place, le Swend ne pourra pas avoir lieu.',
      );
      expect(TextesImprevu.titreConfirmationAnnulation, 'Annuler ce Swend ?');
      expect(
        TextesImprevu.corpsConfirmationAnnulation,
        'Cette action est définitive. L’autre personne sera prévenue.',
      );
      expect(TextesImprevu.titreChoix, 'Tu ne peux plus être là ?');
      expect(
        TextesImprevu.sousTitreChoix,
        'Sollicite l’un de tes remplaçants :)',
      );
    });
    test('refus de la base au tutoiement', () {
      expect(
        TextesImprevu.erreur('remplacement_accepte'),
        'Quelqu’un a déjà accepté de prendre ta place : tu ne peux plus annuler ce Swend.',
      );
      expect(
        TextesImprevu.erreur('place_deja_prise'),
        'Quelqu’un vient d’accepter de prendre ta place.',
      );
      expect(
        TextesImprevu.erreur(null),
        'Impossible pour le moment. Réessaie.',
      );
    });
  });
}
