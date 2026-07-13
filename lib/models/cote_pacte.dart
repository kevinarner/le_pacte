import 'remplacant.dart';
import 'statut_presence.dart';

/// Représente l'état d'un des deux côtés du pacte (celui de
/// l'initiateur, ou celui du destinataire). Le nom affiché à
/// l'autre participant est TOUJOURS `nomTitulaire`, jamais celui
/// d'un remplaçant — conformément à la règle centrale de l'app.
class CotePacte {
  final String nomTitulaire;
  final List<Remplacant> listeRemplacants;
  StatutPresence statutPresence;

  CotePacte({
    required this.nomTitulaire,
    required this.listeRemplacants,
    this.statutPresence = StatutPresence.titulaire,
  });
}
