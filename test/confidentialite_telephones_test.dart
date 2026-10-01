import 'package:flutter_test/flutter_test.dart';
import 'package:le_pacte/services/pacte_repository.dart';

/// D-024 : l'app ne relit jamais de numéro sur la ligne Swend. La base le
/// garantit aussi (privilèges colonne, tests SQL `96_confidentialite_telephones.sql`).
void main() {
  final colonnes = PacteRepository.colonnesPacte
      .split(',')
      .map((c) => c.trim())
      .toList();

  test('aucune colonne de numéro relue sur un Swend', () {
    expect(colonnes.where((c) => c.contains('telephone')), isEmpty);
    expect(colonnes, isNot(contains('*')));
  });

  test('les colonnes utilisées par l\'app sont toujours relues', () {
    expect(colonnes, [
      'id',
      'type',
      'statut',
      'dates_proposees',
      'date_retenue',
      'nombre_echanges_date',
      'restaurant_id',
      'initiateur_id',
      'initiateur_nom',
      'destinataire_id',
      'destinataire_nom',
      'date_minimale',
      'created_at',
    ]);
  });
}
