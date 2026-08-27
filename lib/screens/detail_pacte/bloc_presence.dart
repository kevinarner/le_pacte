import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/pacte.dart';
import '../../models/statut_presence.dart';
import '../../services/pacte_repository.dart';
import 'choisir_remplacant_screen.dart';

/// Bloc affiché une fois le pacte confirmé : permet, à tout moment avant
/// le jour J, de déclarer qu'on n'est finalement plus disponible et de
/// déléguer sa présence à l'un de ses remplaçants.
class BlocPresence extends StatelessWidget {
  final Pacte pacte;
  final bool jeSuisInitiateur;
  final VoidCallback onChanged;

  const BlocPresence({
    super.key,
    required this.pacte,
    required this.jeSuisInitiateur,
    required this.onChanged,
  });

  CotePacte get _monCote => jeSuisInitiateur ? pacte.initiateur : pacte.destinataire;
  CotePacte get _coteAutrePartie => jeSuisInitiateur ? pacte.destinataire : pacte.initiateur;

  @override
  Widget build(BuildContext context) {
    if (_monCote.statutPresence != StatutPresence.titulaire) {
      return const Text(
        "Tu as délégué ta présence à un remplaçant.",
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _choisirRemplacant(context),
        icon: const Icon(Icons.person_search, size: 18),
        label: const Text("Je ne suis finalement plus disponible"),
      ),
    );
  }

  void _choisirRemplacant(BuildContext context) async {
    final choix = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChoisirRemplacantScreen(
          pacteId: pacte.id,
          cote: jeSuisInitiateur ? 'initiateur' : 'destinataire',
          cotePacte: _monCote,
          nomAutrePartie: _coteAutrePartie.nomTitulaire,
          type: pacte.type,
          dates: pacte.dateRetenue != null ? [pacte.dateRetenue!] : [],
        ),
      ),
    );
    if (choix != null) {
      // L'autre partie reçoit la même information que si on venait
      // simplement d'être confirmé — aucune trace visible du nom du
      // remplaçant dans le pacte affiché.
      _monCote.statutPresence = StatutPresence.remplacantSollicite;
      // Si l'autre côté avait déjà délégué, le déclencheur côté base
      // vient d'annuler le pacte : on relit son statut pour le savoir
      // tout de suite, sans attendre une réouverture de l'écran.
      pacte.statut = await PacteRepository.statutActuel(pacte.id);
      onChanged();
    }
  }
}
