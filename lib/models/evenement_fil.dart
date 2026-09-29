import '../utils/noms.dart';

/// Un changement d'état d'une demande "Un imprévu ?", enregistré par la
/// base dans le fil titulaire ↔ personne de confiance (table
/// `evenements_fil`, écrite uniquement par un déclencheur). Affiché dans
/// la conversation, à sa place chronologique parmi les messages.
class EvenementFil {
  final String id;
  final String remplacantId;
  final String code;
  final DateTime createdAt;

  EvenementFil({
    required this.id,
    required this.remplacantId,
    required this.code,
    required this.createdAt,
  });

  /// Le texte selon qui regarde : la personne de confiance ([vuParTiers])
  /// ou le titulaire. [autre] est le prénom de l'interlocuteur (le
  /// titulaire vu du tiers, le tiers vu du titulaire).
  String texte({required bool vuParTiers, required String autre}) {
    if (vuParTiers) {
      return switch (code) {
        'demande_envoyee' => '$autre t\'a demandé de prendre sa place.',
        'demande_annulee' => '$autre a annulé sa demande.',
        'demande_refusee' =>
          'Tu as refusé de prendre la place ${deNom(autre)}.',
        'demande_acceptee' =>
          'Tu as accepté de prendre la place ${deNom(autre)}.',
        'desistement' => 'Tu ne prends plus la place ${deNom(autre)}.',
        'demande_cloturee' => "La demande n'est plus d'actualité.",
        'indisponibilite_signalee' =>
          "Tu as indiqué à $autre que tu ne seras pas disponible.",
        'disponibilite_retablie' =>
          "Tu as indiqué à $autre que tu es finalement disponible.",
        'swend_commence' => finConversation,
        _ => '',
      };
    }
    return switch (code) {
      'demande_envoyee' => 'Tu as demandé à $autre de prendre ta place.',
      'demande_annulee' => 'Tu as annulé ta demande à $autre.',
      'demande_refusee' => '$autre a refusé de prendre ta place.',
      'demande_acceptee' => '$autre a accepté de prendre ta place.',
      'desistement' => '$autre ne peut finalement plus prendre ta place.',
      'demande_cloturee' => "La demande à $autre n'est plus d'actualité.",
      'indisponibilite_signalee' =>
        '$autre ne sera pas disponible en cas d\'imprévu.',
      'disponibilite_retablie' =>
        '$autre est de nouveau disponible en cas d\'imprévu.',
      'swend_commence' => finConversation,
      _ => '',
    };
  }

  /// Dernier événement d'une conversation de l'imprévu, ajouté par la base
  /// à l'heure du Swend (D-023a). Identique pour les deux lecteurs et jamais
  /// « non lu » : ce n'est pas une action de l'interlocuteur.
  static const finConversation =
      'Le Swend a commencé.\nCette conversation est désormais terminée.';

  /// Vrai si l'événement vient de l'interlocuteur et me concerne
  /// directement : il rend la conversation "non lue" et s'affiche en box
  /// sur l'accueil (D-015). La demande reçue a déjà sa propre carte ("Une
  /// demande t'attend") et la clôture automatique n'est pas une action de
  /// l'interlocuteur : ni l'une ni l'autre ne compte ici.
  bool concerneLecteur({required bool vuParTiers}) => vuParTiers
      ? code == 'demande_annulee'
      : const {
          'demande_refusee',
          'demande_acceptee',
          'desistement',
          'indisponibilite_signalee',
          'disponibilite_retablie',
        }.contains(code);
}
