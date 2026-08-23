import 'package:flutter/material.dart';

import 'type_repas.dart';

class Restaurant {
  /// Identifiant de la ligne en base.
  String? id;
  String nom;
  String lien;

  /// Créneaux horaires réellement proposés par le restaurant, par type
  /// de repas.
  List<TimeOfDay> creneauxDejeuner;
  List<TimeOfDay> creneauxDiner;

  Restaurant({
    this.id,
    required this.nom,
    required this.lien,
    this.creneauxDejeuner = const [],
    this.creneauxDiner = const [],
  });

  List<TimeOfDay> creneaux(TypeRepas type) =>
      type == TypeRepas.dejeuner ? creneauxDejeuner : creneauxDiner;
}
