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
        'demande_refusee' => 'Tu as refusé de prendre la place ${deNom(autre)}.',
        'demande_acceptee' => 'Tu as accepté de prendre la place ${deNom(autre)}.',
        'desistement' => 'Tu ne prends plus la place ${deNom(autre)}.',
        'demande_cloturee' => "La demande n'est plus d'actualité.",
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
      _ => '',
    };
  }
}
