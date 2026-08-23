import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/pacte_repository.dart';

/// Bloc affiché quand le destinataire doit répondre à un pacte :
/// accepter ou refuser. La délégation à un remplaçant n'intervient
/// que plus tard, une fois le pacte confirmé, si l'un des deux devient
/// indisponible (voir BlocPresence) — pas dès cette réponse initiale.
class BlocReponse extends StatelessWidget {
  final Pacte pacte;
  final VoidCallback onChanged;
  const BlocReponse({super.key, required this.pacte, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Que souhaites-tu faire ?', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            await PacteRepository.mettreAJourStatut(pacte.id, StatutPacte.confirme);
            pacte.restaurantRetenu = pacte.restaurantsProposes.first;
            pacte.statut = StatutPacte.confirme;
            onChanged();
          },
          child: const Text('Accepter le pacte'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await PacteRepository.mettreAJourStatut(pacte.id, StatutPacte.annule);
            pacte.statut = StatutPacte.annule;
            onChanged();
          },
          child: const Text('Refuser le pacte'),
        ),
      ],
    );
  }
}
