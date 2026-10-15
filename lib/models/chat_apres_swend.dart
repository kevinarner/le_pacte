import '../utils/date_fr.dart';
import '../utils/noms.dart';

/// Chat après le Swend (D-023b) : ouvert par la base quelques heures après
/// un Swend qui a eu lieu, entre les deux titulaires d'origine et le
/// remplaçant sélectionné s'il existe (3 personnes au plus). Totalement
/// séparé des conversations d'imprévu. Les participants et leurs prénoms
/// sont figés à l'ouverture ; l'app ne décide rien de l'accès.

enum RoleChat { initiateur, destinataire, remplacant }

RoleChat? _role(String? code) => switch (code) {
  'initiateur' => RoleChat.initiateur,
  'destinataire' => RoleChat.destinataire,
  'remplacant' => RoleChat.remplacant,
  _ => null,
};

/// Chat fermé par le scellement d'un nouveau Swend entre deux de ses
/// participants (D-023c). Même texte que le message système écrit par la
/// base dans la conversation.
const texteChatFermeNouveauSwend =
    'Un nouveau Swend a été scellé.\nCe chat est désormais fermé pour préserver le silence.';

/// Fiche d'un Swend passé dont le chat est fermé (D-023c).
const titreConversationFermee = 'Conversation fermée';

/// « Faire un nouveau Swend » depuis la fiche (D-023c).
const libelleNouveauSwend = 'Faire un nouveau Swend';
const titreChoixNouveauSwend = 'Avec qui veux-tu faire un nouveau Swend ?';
const texteSwendDejaEnCoursEntreVous = 'Un Swend est déjà en cours entre vous.';
String texteSwendDejaEnCoursAvec(String prenom) =>
    'Tu as déjà un Swend en cours avec $prenom.';

/// État vide, avant le premier message.
const texteChatVide = 'À vous de débriefer.';

/// Chat d'annulation (D-027 lot 2) : entre les deux titulaires d'un Swend
/// annulé, ouvert à l'annulation, sans push d'ouverture. Même
/// infrastructure que le chat après le Swend, jamais présenté comme un
/// « Alors, ce Swend ? ». Textes proposés (lot 3).
const texteChatAnnulationVide = 'Vous pouvez en reparler ici.';
const titreChatAnnulation = 'Swend annulé';
const enteteBlocAnnulation = 'APRÈS L’ANNULATION';

class ParticipantChat {
  final String id;
  final RoleChat role;

  /// Pour le remplaçant : le titulaire dont il a pris la place.
  final RoleChat? placeDe;

  /// Prénom du compte figé à l'ouverture, ou « Compte supprimé ».
  final String prenom;
  final bool estMoi;
  final bool compteSupprime;

  const ParticipantChat({
    required this.id,
    required this.role,
    required this.prenom,
    this.placeDe,
    this.estMoi = false,
    this.compteSupprime = false,
  });

  factory ParticipantChat.depuis(Map<String, dynamic> j) => ParticipantChat(
    id: j['id'] as String,
    role: _role(j['role'] as String?)!,
    placeDe: _role(j['place_de'] as String?),
    prenom: j['prenom'] as String? ?? 'Compte supprimé',
    estMoi: j['est_moi'] == true,
    compteSupprime: j['compte_supprime'] == true,
  );
}

/// État du chat pour la fiche et « Mes Swends ».
enum EtatChatApres { disponible, nonLu, termine }

class ChatApresSwend {
  final String id;
  final String pacteId;

  /// `apres_swend` (D-023b) ou `annulation` (D-027 lot 2). Une base sans
  /// D-027-02 ne connaît que les chats après le Swend.
  final String nature;
  final DateTime ouvertLe;
  final DateTime? fermeLe;
  final String? motifFermeture;

  /// Je ne l'ai encore jamais ouvert : carte « Alors, ce Swend ? ».
  final bool jamaisOuvert;
  final int nonLus;
  final DateTime? dernierMessageLe;
  final String? dernierExpediteur;
  final List<ParticipantChat> participants;

  const ChatApresSwend({
    required this.id,
    required this.pacteId,
    required this.ouvertLe,
    required this.participants,
    this.nature = 'apres_swend',
    this.fermeLe,
    this.motifFermeture,
    this.jamaisOuvert = false,
    this.nonLus = 0,
    this.dernierMessageLe,
    this.dernierExpediteur,
  });

  factory ChatApresSwend.depuis(Map<String, dynamic> j) => ChatApresSwend(
    id: j['chat_id'] as String,
    pacteId: j['pacte_id'] as String,
    nature: j['nature'] as String? ?? 'apres_swend',
    ouvertLe: DateTime.parse(j['ouvert_le'] as String),
    fermeLe: j['ferme_le'] != null
        ? DateTime.parse(j['ferme_le'] as String)
        : null,
    motifFermeture: j['motif_fermeture'] as String?,
    jamaisOuvert: j['jamais_ouvert'] == true,
    nonLus: (j['non_lus'] as num?)?.toInt() ?? 0,
    dernierMessageLe: j['dernier_message_le'] != null
        ? DateTime.parse(j['dernier_message_le'] as String)
        : null,
    dernierExpediteur: j['dernier_expediteur'] as String?,
    participants: [
      for (final p in (j['participants'] as List? ?? const []))
        ParticipantChat.depuis(p as Map<String, dynamic>),
    ],
  );

  bool get ferme => fermeLe != null;

  /// Chat d'annulation entre les deux titulaires (D-027 lot 2).
  bool get estAnnulation => nature == 'annulation';
  bool get aTrois => participants.length >= 3;

  ParticipantChat? get moi => participants.where((p) => p.estMoi).firstOrNull;
  ParticipantChat? get remplacant =>
      participants.where((p) => p.role == RoleChat.remplacant).firstOrNull;
  ParticipantChat? participant(String id) =>
      participants.where((p) => p.id == id).firstOrNull;

  /// En-tête du chat : « Eliot · David » ou « Eliot · David · Kevin ».
  String get enteteParticipants =>
      participants.map((p) => p.prenom).join(' · ');

  /// Sous le bloc « Après le Swend » : « Avec David » / « Avec David et Kevin ».
  String? get avecQui {
    final autres = [
      for (final p in participants)
        if (!p.estMoi) p.prenom,
    ];
    if (autres.isEmpty) return null;
    if (autres.length == 1) return 'Avec ${autres.first}';
    return 'Avec ${autres.sublist(0, autres.length - 1).join(', ')} et ${autres.last}';
  }

  /// En-tête du chat sous les participants.
  String get sousTitreChat =>
      estAnnulation ? titreChatAnnulation : 'Après le Swend';

  /// État vide, avant le premier message.
  String get texteVide =>
      estAnnulation ? texteChatAnnulationVide : texteChatVide;

  /// Révélation du remplacement, visible à partir de l'ouverture seulement.
  /// Le remplaçant est tutoyé, comme partout pour les personnes de confiance.
  String? get revelation {
    final r = remplacant;
    final m = moi;
    if (r == null || m == null) return null;
    final remplace = participants.where((p) => p.role == r.placeDe).firstOrNull;
    if (remplace == null) return null;
    if (m.id == r.id) return 'Tu as pris la place ${deNom(remplace.prenom)}.';
    if (m.id == remplace.id) return '${r.prenom} a pris ta place.';
    return '${r.prenom} a pris la place ${deNom(remplace.prenom)}.';
  }

  EtatChatApres get etat {
    if (ferme) return EtatChatApres.termine;
    if (nonLus > 0) return EtatChatApres.nonLu;
    return EtatChatApres.disponible;
  }

  /// « David t’a écrit » (dernier expéditeur), si non lu.
  String? get libelleNonLu => nonLus > 0 && dernierExpediteur != null
      ? '$dernierExpediteur t’a écrit'
      : null;

  /// Action de la fiche : « Discuter », « David t’a écrit » ; chat fermé
  /// (D-023c) : « Voir la conversation ».
  String get libelleFiche => switch (etat) {
    EtatChatApres.termine => 'Voir la conversation',
    EtatChatApres.nonLu => libelleNonLu ?? 'Discuter',
    EtatChatApres.disponible => 'Discuter',
  };

  /// Ligne de la carte dans « Mes Swends » : pas de statut lourd pour un
  /// chat fermé (D-023c).
  String get libelleMesSwends => switch (etat) {
    EtatChatApres.termine => 'Voir la conversation',
    EtatChatApres.nonLu => '● ${libelleNonLu ?? 'Nouveau message'}',
    EtatChatApres.disponible => 'Discuter',
  };

  /// « Faire un nouveau Swend » : seulement tant que le chat est ouvert
  /// (D-023c). La base le vérifie aussi.
  bool get peutFaireNouveauSwend => !ferme;

  /// Carte d'accueil : un message non lu, ou l'invitation tant que je n'ai
  /// jamais ouvert le chat. Null : pas de carte.
  /// Chat d'annulation : jamais d'invitation (pas de push d'ouverture),
  /// seulement les messages non lus.
  bool get aUneCarteAccueil =>
      !ferme && (nonLus > 0 || (jamaisOuvert && !estAnnulation));

  /// Titre de la carte d'accueil. Chat à 2 : « David t’a écrit » puis
  /// « 4 nouveaux messages » ; chat à 3 : toujours le dernier expéditeur.
  String get titreCarteAccueil {
    if (nonLus == 0) return 'Alors, ce Swend ?';
    if (nonLus == 1 || aTrois) {
      return libelleNonLu ?? '$nonLus nouveaux messages';
    }
    return '$nonLus nouveaux messages';
  }

  /// Sous-titre de la carte d'accueil (jamais le contenu d'un message).
  String sousTitreCarteAccueil({String? restaurant, DateTime? date}) {
    if (nonLus == 0) return 'Le silence est levé.';
    return [
      estAnnulation ? titreChatAnnulation : 'Après le Swend',
      if (restaurant != null && restaurant.isNotEmpty) restaurant,
      if (date != null) formaterJourEtMois(date),
    ].join(' · ');
  }

  /// Ordre des cartes d'accueil : le dernier message, sinon l'ouverture.
  DateTime get dateTri => dernierMessageLe ?? ouvertLe;
}

/// Au plus 2 cartes « après le Swend » sur l'accueil, les plus récentes
/// d'abord.
List<ChatApresSwend> cartesAccueilApresSwend(List<ChatApresSwend> chats) =>
    (chats.where((c) => c.aUneCarteAccueil).toList()
          ..sort((a, b) => b.dateTri.compareTo(a.dateTri)))
        .take(2)
        .toList();

/// Une personne du chat avec qui faire un nouveau Swend (D-023c) : son
/// identifiant de participant et son prénom, jamais un numéro (D-024).
/// [dejaEnCours] : un Swend est déjà en cours avec elle (vérifié par la base,
/// paire par paire).
class OptionNouveauSwend {
  final String participantId;
  final String prenom;
  final bool dejaEnCours;

  const OptionNouveauSwend({
    required this.participantId,
    required this.prenom,
    this.dejaEnCours = false,
  });

  factory OptionNouveauSwend.depuis(Map<String, dynamic> j) =>
      OptionNouveauSwend(
        participantId: j['participant_id'] as String,
        prenom: j['prenom'] as String? ?? '',
        dejaEnCours: j['deja_en_cours'] == true,
      );
}

class MessageApresSwend {
  final String id;
  final String? participantId;
  final bool systeme;
  final String contenu;
  final DateTime createdAt;

  const MessageApresSwend({
    required this.id,
    required this.contenu,
    required this.createdAt,
    this.participantId,
    this.systeme = false,
  });

  factory MessageApresSwend.depuis(Map<String, dynamic> j) => MessageApresSwend(
    id: j['id'] as String,
    participantId: j['participant_id'] as String?,
    systeme: j['genre'] == 'systeme',
    contenu: j['contenu'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Prénom au-dessus d'une bulle : seulement dans un chat à 3, jamais pour
/// mes propres messages ni pour un message système.
String? auteurAffiche(ChatApresSwend chat, MessageApresSwend m) {
  if (!chat.aTrois || m.systeme) return null;
  final p = m.participantId == null ? null : chat.participant(m.participantId!);
  if (p == null || p.estMoi) return null;
  return p.prenom;
}

/// En-tête du chat : « Swend au Père Lapin » pour « Au Père Lapin » (la
/// préposition du nom est reprise), sinon « Swend · [restaurant] ».
String titreSwendAuRestaurant(String? restaurant) {
  final nom = restaurant?.trim() ?? '';
  if (nom.isEmpty) return 'Swend';
  final m = RegExp(r'^(au|aux)\s+(.+)$', caseSensitive: false).firstMatch(nom);
  if (m != null) return 'Swend ${m.group(1)!.toLowerCase()} ${m.group(2)}';
  return 'Swend · $nom';
}

/// Message d'erreur lisible pour un envoi refusé par la base.
String messageErreurEnvoi(String? code) => switch (code) {
  'message_vide' => 'Le message est vide.',
  'message_trop_long' => 'Le message est trop long (2 000 caractères au plus).',
  'chat_ferme' => 'Cette conversation est terminée.',
  'non_autorise' => "Cette conversation n'est plus accessible.",
  _ => "Le message n'a pas pu être envoyé. Réessaie.",
};

/// Web : le clic sur une notification du chat ouvre l'app avec
/// `?chat_apres=<chat_id>` (lien posé par l'Edge Function). Renvoie le chat.
String? chatDuLien(Uri adresse) {
  final id = adresse.queryParameters['chat_apres']?.trim();
  return (id == null || id.isEmpty) ? null : id;
}

/// La même adresse sans `?chat_apres` : un rechargement ne rouvre pas le chat.
String adresseSansChat(Uri adresse) {
  final autres = Map.of(adresse.queryParameters)..remove('chat_apres');
  final requete = autres.isEmpty
      ? ''
      : '?${Uri(queryParameters: autres).query}';
  final ancre = adresse.hasFragment ? '#${adresse.fragment}' : '';
  return '${adresse.path}$requete$ancre';
}
