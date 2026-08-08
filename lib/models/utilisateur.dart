import 'dart:typed_data';

/// Identité simulée (une des deux perspectives de test : "Moi" / "Mon ami").
/// À remplacer par le vrai compte utilisateur une fois le backend branché.
class Utilisateur {
  String nom;
  Uint8List? photo;

  Utilisateur({required this.nom, this.photo});
}
