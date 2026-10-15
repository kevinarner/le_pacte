import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/models/chat_apres_swend.dart';
import 'package:le_pacte/models/evenement_fil.dart';

/// D-027 lot 3b : chat d'annulation entre titulaires et conversations
/// conservées après annulation, côté app (la base décide de l'accès : tests
/// SQL `99g_annulation_conversations.sql`).
void main() {
  Map<String, dynamic> ligne({
    String? nature,
    bool jamaisOuvert = true,
    int nonLus = 0,
    String? dernier,
  }) => {
    'chat_id': 'c1',
    'pacte_id': 'p1',
    'nature': ?nature,
    'ouvert_le': '2031-10-01T10:00:00Z',
    'ferme_le': null,
    'jamais_ouvert': jamaisOuvert,
    'non_lus': nonLus,
    'dernier_expediteur': dernier,
    'participants': [
      {'id': 'e', 'role': 'initiateur', 'prenom': 'Eliot', 'est_moi': true},
      {'id': 'd', 'role': 'destinataire', 'prenom': 'David'},
    ],
  };

  group('Nature du chat', () {
    test(
      'base sans D-027-02 (pas de colonne nature) : chat après le Swend',
      () {
        final c = ChatApresSwend.depuis(ligne());
        expect(c.nature, 'apres_swend');
        expect(c.estAnnulation, isFalse);
        expect(c.sousTitreChat, 'Après le Swend');
        expect(c.texteVide, 'À vous de débriefer.');
      },
    );
    test(
      'chat d\'annulation : textes propres, jamais « Alors, ce Swend ? »',
      () {
        final c = ChatApresSwend.depuis(ligne(nature: 'annulation'));
        expect(c.estAnnulation, isTrue);
        expect(c.sousTitreChat, 'Swend annulé');
        expect(c.texteVide, 'Vous pouvez en reparler ici.');
        expect(c.revelation, isNull);
        expect(c.avecQui, 'Avec David');
        // Jamais ouvert, sans message : pas de carte d'invitation.
        expect(c.aUneCarteAccueil, isFalse);
        expect(cartesAccueilApresSwend([c]), isEmpty);
        expect(c.peutFaireNouveauSwend, isTrue);
      },
    );
    test('chat d\'annulation : carte seulement pour un message non lu', () {
      final c = ChatApresSwend.depuis(
        ligne(nature: 'annulation', nonLus: 1, dernier: 'David'),
      );
      expect(c.aUneCarteAccueil, isTrue);
      expect(c.titreCarteAccueil, 'David t’a écrit');
      expect(
        c.sousTitreCarteAccueil(restaurant: 'Au père Lapin'),
        'Swend annulé · Au père Lapin',
      );
      expect(c.libelleFiche, 'David t’a écrit');
    });
    test(
      'chat après le Swend inchangé : invitation tant que jamais ouvert',
      () {
        final c = ChatApresSwend.depuis(ligne(nature: 'apres_swend'));
        expect(c.aUneCarteAccueil, isTrue);
        expect(c.titreCarteAccueil, 'Alors, ce Swend ?');
      },
    );
  });

  group('Conversation d\'imprévu fermée par un nouveau Swend (P2)', () {
    final e = EvenementFil(
      id: 'x',
      remplacantId: 'r',
      code: 'fil_ferme',
      createdAt: DateTime.utc(2031, 10, 2),
    );
    test('même texte pour les deux lecteurs', () {
      const texte =
          'Un nouveau Swend a été scellé entre vous.\nCette conversation est désormais fermée.';
      expect(e.texte(vuParTiers: true, autre: 'Eliot'), texte);
      expect(e.texte(vuParTiers: false, autre: 'Kevin'), texte);
    });
    test('jamais « non lu » (événement système)', () {
      expect(e.concerneLecteur(vuParTiers: true), isFalse);
      expect(e.concerneLecteur(vuParTiers: false), isFalse);
    });
  });
}
