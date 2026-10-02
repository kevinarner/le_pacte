import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/models/chat_apres_swend.dart';

/// Chat après le Swend (D-023b) : textes et règles d'affichage. La base
/// reste seule juge de l'accès et de l'ouverture (tests SQL
/// `99b_chat_apres_swend.sql`).
void main() {
  const eliot = 'e';
  const david = 'd';
  const kevin = 'k';

  List<ParticipantChat> participants(
    String moi, {
    bool avecKevin = true,
    RoleChat place = RoleChat.initiateur,
  }) => [
    ParticipantChat(
      id: eliot,
      role: RoleChat.initiateur,
      prenom: 'Eliot',
      estMoi: moi == eliot,
    ),
    ParticipantChat(
      id: david,
      role: RoleChat.destinataire,
      prenom: 'David',
      estMoi: moi == david,
    ),
    if (avecKevin)
      ParticipantChat(
        id: kevin,
        role: RoleChat.remplacant,
        placeDe: place,
        prenom: 'Kevin',
        estMoi: moi == kevin,
      ),
  ];

  ChatApresSwend chat(
    String moi, {
    bool avecKevin = true,
    int nonLus = 0,
    bool jamaisOuvert = false,
    String? dernier,
    DateTime? dernierLe,
    DateTime? ouvertLe,
    DateTime? fermeLe,
    RoleChat place = RoleChat.initiateur,
  }) => ChatApresSwend(
    id: 'c-$moi-${ouvertLe?.millisecondsSinceEpoch ?? 0}',
    pacteId: 'p',
    ouvertLe: ouvertLe ?? DateTime.utc(2031, 10, 13, 21),
    participants: participants(moi, avecKevin: avecKevin, place: place),
    nonLus: nonLus,
    jamaisOuvert: jamaisOuvert,
    dernierExpediteur: dernier,
    dernierMessageLe: dernierLe,
    fermeLe: fermeLe,
    motifFermeture: fermeLe == null ? null : 'nouveau_swend',
  );

  group('Révélation du remplacement', () {
    test('titulaire remplacé, autre titulaire, remplaçant (tutoyé)', () {
      expect(chat(eliot).revelation, 'Kevin a pris votre place.');
      expect(chat(david).revelation, "Kevin a pris la place d'Eliot.");
      expect(chat(kevin).revelation, "Tu as pris la place d'Eliot.");
    });
    test('remplacement côté destinataire', () {
      expect(
        chat(david, place: RoleChat.destinataire).revelation,
        'Kevin a pris votre place.',
      );
      expect(
        chat(eliot, place: RoleChat.destinataire).revelation,
        'Kevin a pris la place de David.',
      );
      expect(
        chat(kevin, place: RoleChat.destinataire).revelation,
        'Tu as pris la place de David.',
      );
    });
    test('sans remplaçant : aucune révélation', () {
      expect(chat(eliot, avecKevin: false).revelation, isNull);
    });
  });

  group('En-têtes et participants', () {
    test('en-tête à 2 et à 3', () {
      expect(chat(eliot, avecKevin: false).enteteParticipants, 'Eliot · David');
      expect(chat(eliot).enteteParticipants, 'Eliot · David · Kevin');
    });
    test('« Avec… » sous le bloc de la fiche', () {
      expect(chat(eliot, avecKevin: false).avecQui, 'Avec David');
      expect(chat(eliot).avecQui, 'Avec David et Kevin');
      expect(chat(kevin).avecQui, 'Avec Eliot et David');
    });
  });

  group('Prénom au-dessus des bulles', () {
    final m = MessageApresSwend(
      id: 'm',
      participantId: kevin,
      contenu: 'Super',
      createdAt: DateTime.utc(2031),
    );
    test('chat à 3 : prénom de l’auteur, jamais pour moi', () {
      expect(auteurAffiche(chat(eliot), m), 'Kevin');
      expect(auteurAffiche(chat(kevin), m), isNull);
    });
    test('chat à 2 : jamais de prénom', () {
      final m2 = MessageApresSwend(
        id: 'm',
        participantId: david,
        contenu: 'Salut',
        createdAt: DateTime.utc(2031),
      );
      expect(auteurAffiche(chat(eliot, avecKevin: false), m2), isNull);
    });
    test('message système : jamais de prénom', () {
      final s = MessageApresSwend(
        id: 's',
        contenu: texteChatFermeNouveauSwend,
        systeme: true,
        createdAt: DateTime.utc(2031),
      );
      expect(auteurAffiche(chat(eliot), s), isNull);
    });
  });

  test('état vide et chat fermé (D-023c, prévu)', () {
    expect(texteChatVide, 'À vous de débriefer.');
    expect(
      texteChatFermeNouveauSwend,
      'Un nouveau Swend a été scellé.\nLe chat est désormais fermé pour préserver le silence.',
    );
  });

  group('Fiche et Mes Swends', () {
    test('Discuter / David vous a écrit / Conversation terminée', () {
      expect(chat(eliot).libelleFiche, 'Discuter');
      expect(
        chat(eliot, nonLus: 2, dernier: 'David').libelleFiche,
        'David vous a écrit',
      );
      expect(
        chat(eliot, fermeLe: DateTime.utc(2031, 11)).libelleFiche,
        'Conversation terminée',
      );
      expect(chat(eliot).libelleMesSwends, 'Discuter');
      expect(
        chat(eliot, nonLus: 1, dernier: 'David').libelleMesSwends,
        '● David vous a écrit',
      );
      expect(
        chat(eliot, fermeLe: DateTime.utc(2031, 11)).libelleMesSwends,
        'Conversation terminée',
      );
    });
  });

  group('Accueil', () {
    test(
      'invitation « Alors, ce Swend ? » tant que le chat n’a jamais été ouvert',
      () {
        final c = chat(eliot, jamaisOuvert: true);
        expect(c.aUneCarteAccueil, isTrue);
        expect(c.titreCarteAccueil, 'Alors, ce Swend ?');
        expect(c.sousTitreCarteAccueil(), 'Le silence est levé.');
        expect(chat(eliot).aUneCarteAccueil, isFalse);
      },
    );
    test(
      'message non lu : expéditeur, puis « N nouveaux messages » (chat à 2)',
      () {
        final un = chat(eliot, avecKevin: false, nonLus: 1, dernier: 'David');
        expect(un.titreCarteAccueil, 'David vous a écrit');
        expect(
          un.sousTitreCarteAccueil(
            restaurant: 'Au Père Lapin',
            date: DateTime.utc(2026, 10, 13, 18), // 20:00 à Paris
          ),
          'Après le Swend · Au Père Lapin · 13 octobre',
        );
        expect(
          chat(
            eliot,
            avecKevin: false,
            nonLus: 4,
            dernier: 'David',
          ).titreCarteAccueil,
          '4 nouveaux messages',
        );
      },
    );
    test('chat à 3 : toujours le dernier expéditeur', () {
      expect(
        chat(eliot, nonLus: 4, dernier: 'Kevin').titreCarteAccueil,
        'Kevin vous a écrit',
      );
    });
    test(
      'au plus 2 cartes, triées par dernier message ; rien pour un chat fermé',
      () {
        final a = chat(
          eliot,
          nonLus: 1,
          dernier: 'David',
          dernierLe: DateTime.utc(2031, 10, 14),
          ouvertLe: DateTime.utc(2031, 10, 1),
        );
        final b = chat(
          eliot,
          jamaisOuvert: true,
          ouvertLe: DateTime.utc(2031, 10, 20),
        );
        final c = chat(
          eliot,
          nonLus: 3,
          dernier: 'Kevin',
          dernierLe: DateTime.utc(2031, 10, 18),
          ouvertLe: DateTime.utc(2031, 10, 2),
        );
        final lu = chat(eliot, ouvertLe: DateTime.utc(2031, 10, 25));
        final ferme = chat(
          eliot,
          nonLus: 1,
          dernier: 'David',
          dernierLe: DateTime.utc(2031, 10, 30),
          ouvertLe: DateTime.utc(2031, 10, 3),
          fermeLe: DateTime.utc(2031, 10, 31),
        );
        final cartes = cartesAccueilApresSwend([a, b, c, lu, ferme]);
        expect(cartes, [b, c]);
      },
    );
  });

  group('Lien web direct', () {
    test('?chat_apres=<id> lu puis retiré de l’adresse', () {
      final lien = Uri.parse(
        'https://kevinarner.github.io/le_pacte/?chat_apres=abc-123#/',
      );
      expect(chatDuLien(lien), 'abc-123');
      expect(
        chatDuLien(Uri.parse('https://kevinarner.github.io/le_pacte/')),
        isNull,
      );
      expect(adresseSansChat(lien), '/le_pacte/#/');
    });
  });

  test('en-tête « Swend au Père Lapin »', () {
    expect(titreSwendAuRestaurant('Au Père Lapin'), 'Swend au Père Lapin');
    expect(titreSwendAuRestaurant('Au père Lapin'), 'Swend au père Lapin');
    expect(titreSwendAuRestaurant('Le Comptoir'), 'Swend · Le Comptoir');
    expect(titreSwendAuRestaurant(null), 'Swend');
  });

  test('messages d’erreur d’envoi lisibles (jamais d’erreur brute)', () {
    expect(messageErreurEnvoi('message_trop_long'), contains('2 000'));
    expect(
      messageErreurEnvoi('chat_ferme'),
      'Cette conversation est terminée.',
    );
    expect(
      messageErreurEnvoi(null),
      "Le message n'a pas pu être envoyé. Réessayez.",
    );
  });

  test('lecture du résumé renvoyé par la base', () {
    final c = ChatApresSwend.depuis({
      'chat_id': 'c1',
      'pacte_id': 'p1',
      'ouvert_le': '2031-10-13T21:00:00+00:00',
      'ferme_le': null,
      'motif_fermeture': null,
      'jamais_ouvert': true,
      'non_lus': 2,
      'dernier_message_le': '2031-10-13T22:00:00+00:00',
      'dernier_expediteur': 'Kevin',
      'dernier_de_moi': false,
      'participants': [
        {
          'id': 'a',
          'role': 'initiateur',
          'place_de': null,
          'prenom': 'Eliot',
          'est_moi': true,
          'compte_supprime': false,
        },
        {
          'id': 'b',
          'role': 'destinataire',
          'place_de': null,
          'prenom': 'David',
          'est_moi': false,
          'compte_supprime': false,
        },
        {
          'id': 'c',
          'role': 'remplacant',
          'place_de': 'initiateur',
          'prenom': 'Compte supprimé',
          'est_moi': false,
          'compte_supprime': true,
        },
      ],
    });
    expect(c.enteteParticipants, 'Eliot · David · Compte supprimé');
    expect(c.revelation, 'Compte supprimé a pris votre place.');
    expect(c.nonLus, 2);
    expect(c.titreCarteAccueil, 'Kevin vous a écrit');
  });
}
