import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../models/statut_presence.dart';
import 'choisir_remplacant_screen.dart';

/// Bloc affiché quand le destinataire doit répondre à un pacte :
/// les 3 options (accepter, déléguer, refuser).
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
          onPressed: () {
            pacte.destinataire.statutPresence = StatutPresence.titulaire;
            pacte.statut = StatutPacte.accepteEnAttenteClassement;
            onChanged();
          },
          child: const Text('Accepter pour moi'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _choisirRemplacant(context),
          child: const Text('Accepter et déléguer à un remplaçant'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: pacte.nombreRefus >= 2
              ? null
              : () {
                  pacte.nombreRefus += 1;
                  pacte.statut = StatutPacte.refuseContreProposition;
                  onChanged();
                },
          child: Text(pacte.nombreRefus >= 2
              ? 'Refuser (limite de 2 refus atteinte)'
              : 'Refuser et proposer une autre date (${pacte.nombreRefus}/2)'),
        ),
      ],
    );
  }

  void _choisirRemplacant(BuildContext context) async {
    final choix = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChoisirRemplacantScreen(cote: pacte.destinataire)),
    );
    if (choix != null) {
      // L'initiateur reçoit la même notification que "accepte pour soi" —
      // aucune trace visible du nom du remplaçant dans le pacte affiché.
      pacte.destinataire.statutPresence = StatutPresence.remplacantSollicite;
      pacte.statut = StatutPacte.accepteEnAttenteClassement;
      onChanged();
    }
  }
}
