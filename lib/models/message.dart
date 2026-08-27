/// Un message du fil de discussion entre un titulaire et l'un de ses
/// remplaçants (voir remplacant_id).
class Message {
  final String id;
  final String remplacantId;
  final String expediteurId;
  final String contenu;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.remplacantId,
    required this.expediteurId,
    required this.contenu,
    required this.createdAt,
  });
}
