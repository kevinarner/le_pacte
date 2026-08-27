import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/pacte.dart';
import '../../models/statut_presence.dart';
import '../../services/pacte_repository.dart';
import 'mes_remplacants_screen.dart';

/// Bloc affiché une fois le pacte confirmé : donne accès, à tout
/// moment, à ses propres remplaçants — pour en ajouter, discuter avec
/// ceux qui ont un compte, ou déléguer sa présence à l'un d'eux si on
/// devient finalement indisponible.
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
    final nb = _monCote.listeRemplacants.where((r) => r.estRempli).length;
    final delegue = _monCote.statutPresence != StatutPresence.titulaire;

    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => _ouvrirMesRemplacants(context),
        icon: const Icon(Icons.people_outline, size: 18),
        label: Text(
          delegue
              ? 'Mes remplaçants — tu as délégué ta présence'
              : 'Mes remplaçants${nb > 0 ? ' ($nb)' : ''}',
        ),
      ),
    );
  }

  void _ouvrirMesRemplacants(BuildContext context) async {
    final quelqueChoseAChange = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MesRemplacantsScreen(
          pacteId: pacte.id,
          cote: jeSuisInitiateur ? 'initiateur' : 'destinataire',
          cotePacte: _monCote,
          nomAutrePartie: _coteAutrePartie.nomTitulaire,
          type: pacte.type,
          dates: pacte.dateRetenue != null ? [pacte.dateRetenue!] : [],
        ),
      ),
    );
    if (quelqueChoseAChange == true) {
      _monCote.statutPresence = _monCote.listeRemplacants.any((r) => r.selectionne)
          ? StatutPresence.remplacantSollicite
          : StatutPresence.titulaire;
      // Le déclencheur côté base peut avoir annulé le pacte si l'autre
      // partie avait déjà délégué elle aussi.
      pacte.statut = await PacteRepository.statutActuel(pacte.id);
      onChanged();
    }
  }
}
