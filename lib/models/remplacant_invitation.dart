import 'statut_pacte.dart';
import 'type_repas.dart';

/// Un pacte où l'utilisateur connecté a été ajouté comme remplaçant
/// potentiel (côté initiateur ou destinataire) — pas forcément celui
/// qui a été délégué.
class RemplacantInvitation {
  final String remplacantId;
  final String pacteId;
  final String nomTitulaire;
  final TypeRepas type;
  final DateTime? dateRetenue;
  final StatutPacte statutPacte;

  RemplacantInvitation({
    required this.remplacantId,
    required this.pacteId,
    required this.nomTitulaire,
    required this.type,
    required this.dateRetenue,
    required this.statutPacte,
  });
}
