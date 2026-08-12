import 'package:flutter/material.dart';

import 'type_repas.dart';

class Restaurant {
  String nom;
  String lien;

  /// Créneaux horaires réellement proposés par le restaurant, par type
  /// de repas.
  List<TimeOfDay> creneauxDejeuner;
  List<TimeOfDay> creneauxDiner;

  Restaurant({
    required this.nom,
    required this.lien,
    this.creneauxDejeuner = const [],
    this.creneauxDiner = const [],
  });

  List<TimeOfDay> creneaux(TypeRepas type) =>
      type == TypeRepas.dejeuner ? creneauxDejeuner : creneauxDiner;
}
