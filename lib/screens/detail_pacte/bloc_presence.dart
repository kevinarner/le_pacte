import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/pacte.dart';
import '../../models/remplacant.dart';
import '../../models/statut_presence.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';
import 'mes_remplacants_screen.dart';

/// "En cas d'imprévu" (titulaire) : résume, sur la page du Swend, la
/// personne qui a accepté de prendre ma place (s'il y en a une) ou les
/// personnes prévues, et donne accès à `MesRemplacantsScreen` pour gérer
/// la liste (préparation uniquement).
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

  CotePacte get _monCote =>
      jeSuisInitiateur ? pacte.initiateur : pacte.destinataire;
  CotePacte get _coteAutrePartie =>
      jeSuisInitiateur ? pacte.destinataire : pacte.initiateur;

  @override
  Widget build(BuildContext context) {
    final remplacants = _monCote.listeRemplacants
        .where((r) => r.estRempli)
        .toList();
    Remplacant? designe;
    for (final r in remplacants) {
      if (r.selectionne) {
        designe = r;
        break;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "EN CAS D'IMPRÉVU",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.texteAttenue,
                letterSpacing: 0.06,
              ),
            ),
            const SizedBox(height: 8),
            if (designe != null) ...[
              Text(
                '${designe.prenom} prendra votre place',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Votre Swend reste scellé.',
                style: TextStyle(fontSize: 12, color: AppColors.texteAttenue),
              ),
              const SizedBox(height: 10),
              if (designe.profilId != null)
                FilledButton.icon(
                  onPressed: () => _ouvrirChat(context, designe!),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: Text('Écrire à ${designe.prenom}'),
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _ouvrirMesRemplacants(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Voir les personnes prévues',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ] else ...[
              Text(
                remplacants.isEmpty
                    ? 'Aucune personne prévue'
                    : remplacants.map((r) => r.prenom).join(', '),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                remplacants.length > 1
                    ? 'Ces personnes pourront prendre votre place si vous ne pouvez finalement pas venir.'
                    : remplacants.length == 1
                    ? 'Cette personne pourra prendre votre place si vous ne pouvez finalement pas venir.'
                    : 'Une personne de confiance pourra prendre votre place si vous ne pouvez finalement pas venir.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.texteAttenue,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _ouvrirMesRemplacants(context),
                icon: const Icon(Icons.group_outlined, size: 16),
                label: Text(
                  remplacants.isEmpty
                      ? 'Ajouter des personnes'
                      : 'Gérer les personnes prévues',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _ouvrirChat(BuildContext context, Remplacant r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          remplacantId: r.id!,
          nomInterlocuteur: r.nomComplet,
          telephoneInterlocuteur: r.telephone,
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
      _monCote.statutPresence =
          _monCote.listeRemplacants.any((r) => r.selectionne)
          ? StatutPresence.remplacantSollicite
          : StatutPresence.titulaire;
      // Le déclencheur côté base peut avoir annulé le pacte si l'autre
      // partie avait déjà délégué elle aussi.
      pacte.statut = await PacteRepository.statutActuel(pacte.id);
      onChanged();
    }
  }
}
