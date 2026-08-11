import 'cote_pacte.dart';
import 'restaurant.dart';
import 'statut_pacte.dart';
import 'type_repas.dart';

class Pacte {
  final String id;
  final TypeRepas type;
  List<DateTime> datesProposees;
  DateTime? dateRetenue;
  int nombreEchangesDate;
  final List<Restaurant> restaurantsProposes;
  Restaurant? restaurantRetenu;
  List<int>? classementInitiateur; // indices des restaurants, du préféré au moins préféré
  List<int>? classementDestinataire;
  StatutPacte statut;
  final CotePacte initiateur;
  final CotePacte destinataire;

  Pacte({
    required this.id,
    required this.type,
    required this.datesProposees,
    this.dateRetenue,
    this.nombreEchangesDate = 0,
    required this.restaurantsProposes,
    required this.initiateur,
    required this.destinataire,
    this.statut = StatutPacte.enAttenteChoixDateDestinataire,
  });
}
