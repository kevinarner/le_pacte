import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/pacte_repository.dart';

/// Bloc de simulation du garde-fou anti-désistement (J-7 / J-3 / J-1),
/// en attendant que ces notifications soient gérées par le backend.
class BlocCascade extends StatelessWidget {
  final Pacte pacte;
  final VoidCallback onChanged;
  const BlocCascade({super.key, required this.pacte, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Simulation du garde-fou anti-désistement',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          "Ces boutons remplacent, en test, les notifications automatiques "
          "réelles (J-7, J-3, J-1) qui seront gérées par le backend plus tard.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () async {
            await PacteRepository.mettreAJourStatut(pacte.id, StatutPacte.maintenu);
            pacte.statut = StatutPacte.maintenu;
            onChanged();
          },
          child: const Text('Simuler J-1 : maintenu (les deux ont confirmé)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            await PacteRepository.mettreAJourStatut(pacte.id, StatutPacte.annule);
            pacte.statut = StatutPacte.annule;
            onChanged();
          },
          child: const Text("Simuler J-1 : annulé (aucun remplaçant trouvé)"),
        ),
      ],
    );
  }
}
