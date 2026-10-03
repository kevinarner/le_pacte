import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/models/chat_apres_swend.dart';
import 'package:le_pacte/models/nouveau_swend.dart';
import 'package:le_pacte/screens/creer_pacte/choix_nouveau_swend_screen.dart';
import 'package:le_pacte/screens/detail_pacte/bloc_apres_swend.dart';
import 'package:le_pacte/services/pacte_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// « Faire un nouveau Swend » et chat fermé (D-023c) : affichage. La base
/// reste seule juge de la fermeture, du Swend en cours par paire et de la
/// création (tests SQL `99e_nouveau_swend.sql`, E2E `28_nouveau_swend`).
void main() {
  ChatApresSwend chat({bool aTrois = false, DateTime? fermeLe}) =>
      ChatApresSwend(
        id: 'c',
        pacteId: 'p',
        ouvertLe: DateTime.utc(2031, 10, 13, 21),
        fermeLe: fermeLe,
        motifFermeture: fermeLe == null ? null : 'nouveau_swend',
        participants: [
          const ParticipantChat(
            id: 'a',
            role: RoleChat.initiateur,
            prenom: 'Alma',
            estMoi: true,
          ),
          const ParticipantChat(
            id: 'd',
            role: RoleChat.destinataire,
            prenom: 'Diane',
          ),
          if (aTrois)
            const ParticipantChat(
              id: 'k',
              role: RoleChat.remplacant,
              placeDe: RoleChat.destinataire,
              prenom: 'Kevin',
            ),
        ],
      );

  Future<void> afficher(WidgetTester tester, Widget w) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: w)),
    ),
  );

  group('Fiche « Après le Swend »', () {
    testWidgets(
      'chat ouvert : « Discuter » puis « Faire un nouveau Swend » en dessous',
      (tester) async {
        var nouveau = 0;
        await afficher(
          tester,
          BlocApresSwend(
            chat: chat(),
            onOuvrir: () {},
            onNouveauSwend: () => nouveau++,
          ),
        );
        expect(find.text('Discuter'), findsOneWidget);
        expect(find.text('Faire un nouveau Swend'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Discuter')).dy <
              tester.getTopLeft(find.text('Faire un nouveau Swend')).dy,
          isTrue,
        );
        expect(find.text('Conversation fermée'), findsNothing);
        await tester.tap(find.text('Faire un nouveau Swend'));
        expect(nouveau, 1);
      },
    );

    testWidgets(
      'chat fermé : « Voir la conversation », plus de création, texte sobre',
      (tester) async {
        var ouvert = 0;
        await afficher(
          tester,
          BlocApresSwend(
            chat: chat(fermeLe: DateTime.utc(2031, 11)),
            onOuvrir: () => ouvert++,
            onNouveauSwend: () {},
          ),
        );
        expect(find.text('Voir la conversation'), findsOneWidget);
        expect(find.text('Discuter'), findsNothing);
        expect(find.text('Faire un nouveau Swend'), findsNothing);
        expect(find.text('Conversation fermée'), findsOneWidget);
        expect(
          find.text(
            'Un nouveau Swend a été scellé. Ce chat est désormais fermé pour préserver le silence.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Voir la conversation'));
        expect(ouvert, 1);
      },
    );

    test('Mes Swends : pas de statut lourd pour un chat fermé', () {
      final c = chat(fermeLe: DateTime.utc(2031, 11));
      expect(c.libelleMesSwends, 'Voir la conversation');
      expect(c.peutFaireNouveauSwend, isFalse);
      expect(chat().peutFaireNouveauSwend, isTrue);
      expect(c.aUneCarteAccueil, isFalse);
    });
  });

  group('Chat à 2', () {
    test('« Avec qui ? » sauté : directement « Quand et où ? »', () {
      expect(etapesCreation(depuisChat: true), [
        EtapeCreation.quandEtOu,
        EtapeCreation.remplacants,
      ]);
      expect(etapesCreation(depuisChat: false), [
        EtapeCreation.avecQui,
        EtapeCreation.quandEtOu,
        EtapeCreation.remplacants,
      ]);
    });

    test('Swend déjà en cours entre vous : texte, refus serveur reconnu', () {
      expect(
        texteSwendDejaEnCoursEntreVous,
        'Un Swend est déjà en cours entre vous.',
      );
      const refus = PostgrestException(
        message: 'swend_deja_en_cours',
        code: 'P0001',
      );
      expect(PacteRepository.codeErreurMetier(refus), 'swend_deja_en_cours');
      expect(
        PacteRepository.codeErreurMetier(
          const PostgrestException(message: 'chat_ferme'),
        ),
        'chat_ferme',
      );
    });
  });

  group('Chat à 3 : choix de la personne', () {
    const options = [
      OptionNouveauSwend(participantId: 'd', prenom: 'Diane'),
      OptionNouveauSwend(
        participantId: 'k',
        prenom: 'Kevin',
        dejaEnCours: true,
      ),
    ];

    final choisis = <String>[];
    Future<void> choix(WidgetTester tester) {
      choisis.clear();
      return tester.pumpWidget(
        MaterialApp(
          home: ChoixNouveauSwendScreen(
            options: options,
            onChoisir: (o) async {
              choisis.add(o.participantId);
              return false;
            },
          ),
        ),
      );
    }

    testWidgets(
      'les deux autres personnes, au même niveau, sans rôle ni recherche ni « Continuer »',
      (tester) async {
        await choix(tester);
        expect(
          find.text('Avec qui veux-tu faire un nouveau Swend ?'),
          findsOneWidget,
        );
        expect(find.text('Diane'), findsOneWidget);
        expect(find.text('Kevin'), findsOneWidget);
        expect(find.text('Alma'), findsNothing);
        for (final interdit in [
          'titulaire',
          'remplaçant',
          'Remplaçant',
          'Continuer',
          'Rechercher',
          'Ajouter',
        ]) {
          expect(find.textContaining(interdit), findsNothing, reason: interdit);
        }
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        // Même style de carte pour les deux.
        expect(find.byType(Card), findsNWidgets(2));
      },
    );

    testWidgets(
      'Swend en cours avec Kevin seulement : seule sa carte est désactivée',
      (tester) async {
        await choix(tester);
        expect(
          find.text('Tu as déjà un Swend en cours avec Kevin.'),
          findsOneWidget,
        );
        expect(find.textContaining('avec Diane'), findsNothing);
        final inkwells = tester
            .widgetList<InkWell>(find.byType(InkWell))
            .toList();
        expect(inkwells.length, 2);
        expect(inkwells[0].onTap, isNotNull); // Diane
        expect(inkwells[1].onTap, isNull); // Kevin
        await tester.tap(find.text('Kevin'));
        await tester.pumpAndSettle();
        expect(choisis, isEmpty);
      },
    );

    testWidgets('toucher une personne disponible ouvre directement la création', (
      tester,
    ) async {
      await choix(tester);
      await tester.tap(find.text('Diane'));
      await tester.pumpAndSettle();
      // Par son identifiant de participant (jamais un numéro), sans autre étape.
      expect(choisis, ['d']);
    });
  });

  test('textes D-023c au tutoiement', () {
    final textes = [
      texteChatFermeNouveauSwend,
      titreConversationFermee,
      libelleNouveauSwend,
      titreChoixNouveauSwend,
      texteSwendDejaEnCoursAvec('Kevin'),
      chat(fermeLe: DateTime.utc(2031)).libelleFiche,
      chat(fermeLe: DateTime.utc(2031)).libelleMesSwends,
    ];
    final vouvoiement = RegExp(
      r'\b(vous|votre|vos|[a-zé]+ez)\b',
      caseSensitive: false,
    );
    for (final t in textes) {
      expect(vouvoiement.hasMatch(t), isFalse, reason: t);
    }
    // « entre vous » : les deux personnes ensemble (texte de la règle).
    expect(
      texteSwendDejaEnCoursEntreVous.contains(
        RegExp(r'\b(votre|vos|[a-zé]+ez)\b'),
      ),
      isFalse,
    );
    expect(titreChoixNouveauSwend.contains('veux-tu'), isTrue);
    expect(
      texteSwendDejaEnCoursAvec('Kevin'),
      'Tu as déjà un Swend en cours avec Kevin.',
    );
  });
}
