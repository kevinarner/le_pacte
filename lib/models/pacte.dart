import 'cote_pacte.dart';
import 'restaurant.dart';
import 'statut_pacte.dart';
import 'type_repas.dart';

class Pacte {
  final String id;
  final TypeRepas type;
  DateTime? date;
  final bool dateAutomatique;
  final List<Restaurant> restaurantsProposes;
  Restaurant? restaurantRetenu;
  List<int>? classementInitiateur; // indices des restaurants, du préféré au moins préféré
  List<int>? classementDestinataire;
  StatutPacte statut;
  int nombreRefus;
  final CotePacte initiateur;
  final CotePacte destinataire;

  Pacte({
    required this.id,
    required this.type,
    required this.date,
    required this.dateAutomatique,
    required this.restaurantsProposes,
    required this.initiateur,
    required this.destinataire,
    this.statut = StatutPacte.enAttenteReponse,
    this.nombreRefus = 0,
  });
}
