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

  /// Première date possible pour ce Swend (D-025), fixée par la base à la
  /// création ; null : pas de limite (créé par un compte fondateur, ou
  /// antérieur à la règle).
  final DateTime? dateMinimale;
  final List<Restaurant> restaurantsProposes;
  Restaurant? restaurantRetenu;
  StatutPacte statut;
  final CotePacte initiateur;
  final CotePacte destinataire;

  Pacte({
    required this.id,
    required this.type,
    required this.datesProposees,
    this.dateRetenue,
    this.nombreEchangesDate = 0,
    this.dateMinimale,
    required this.restaurantsProposes,
    required this.initiateur,
    required this.destinataire,
    this.statut = StatutPacte.enAttenteChoixDateDestinataire,
  });
}
