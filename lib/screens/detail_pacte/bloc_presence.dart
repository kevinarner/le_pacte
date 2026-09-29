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
/// personnes prévues, avec deux actions distinctes : "Modifier ma liste"
/// (`MesRemplacantsScreen`, préparation uniquement) et "Discuter" (choix
/// d'une conversation avec une personne de la liste déjà sur Swend).
///
/// [fige] (D-023a) : l'heure du Swend est passée — plus de gestion de la
/// liste, seulement, s'il y en a, la relecture des conversations.
class BlocPresence extends StatelessWidget {
  final Pacte pacte;
  final bool jeSuisInitiateur;
  final bool fige;
  final VoidCallback onChanged;

  const BlocPresence({
    super.key,
    required this.pacte,
    required this.jeSuisInitiateur,
    this.fige = false,
    required this.onChanged,
  });

  CotePacte get _monCote =>
      jeSuisInitiateur ? pacte.initiateur : pacte.destinataire;
  CotePacte get _coteAutrePartie =>
      jeSuisInitiateur ? pacte.destinataire : pacte.initiateur;

  @override
  Widget build(BuildContext context) {
    final remplacants = Remplacant.comptesDAbord(
      _monCote.listeRemplacants.where((r) => r.estRempli),
    );
    // Ceux qui peuvent encore être sollicités : ni refus, ni désistement,
    // ni demande clôturée, ni indisponibilité signalée par la personne
    // (la liste complète reste dans "Modifier ma liste").
    final disponibles = remplacants.where((r) => !r.estIndisponible).toList();
    Remplacant? designe;
    for (final r in remplacants) {
      if (r.selectionne) {
        designe = r;
        break;
      }
    }

    if (fige) return _blocFige(context, remplacants, designe);

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
              // Une place acceptée ne coupe jamais l'accès aux autres
              // conversations de la liste.
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _choisirConversation(context, remplacants),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('Discuter'),
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
                    : disponibles.isEmpty
                    ? 'Aucune personne disponible pour le moment.'
                    : disponibles
                          .map((r) => r.prenom.trim())
                          .where((p) => p.isNotEmpty)
                          .join(', '),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                remplacants.isNotEmpty && disponibles.isEmpty
                    ? "Vous pouvez ajouter quelqu'un depuis « Modifier ma liste »."
                    : disponibles.length > 1
                    ? 'Ces personnes pourront prendre votre place si vous ne pouvez finalement pas venir.'
                    : disponibles.length == 1
                    ? 'Cette personne pourra prendre votre place si vous ne pouvez finalement pas venir.'
                    : 'Une personne de confiance pourra prendre votre place si vous ne pouvez finalement pas venir.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.texteAttenue,
                ),
              ),
              const SizedBox(height: 10),
              if (remplacants.isEmpty)
                OutlinedButton.icon(
                  onPressed: () => _ouvrirMesRemplacants(context),
                  icon: const Icon(Icons.group_outlined, size: 16),
                  label: const Text('Ajouter des personnes'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: _styleActionCompacte,
                        onPressed: () => _ouvrirMesRemplacants(context),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Modifier ma liste'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: _styleActionCompacte,
                        onPressed: () =>
                            _choisirConversation(context, remplacants),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Discuter'),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Après l'heure du Swend : qui a pris la place (s'il y en a une) et la
  /// relecture des conversations, sans aucune action de gestion. Rien du
  /// tout s'il n'y a ni remplacement ni conversation possible.
  Widget _blocFige(
    BuildContext context,
    List<Remplacant> remplacants,
    Remplacant? designe,
  ) {
    final avecConversation = remplacants.any(
      (r) => r.profilId != null && r.id != null,
    );
    if (designe == null && !avecConversation) return const SizedBox.shrink();
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
                '${designe.prenom} a pris votre place',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (avecConversation)
              OutlinedButton.icon(
                onPressed: () => _choisirConversation(context, remplacants),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('Relire une conversation'),
              ),
          ],
        ),
      ),
    );
  }

  /// Deux actions côte à côte : marges réduites pour tenir sur une ligne.
  static final _styleActionCompacte = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 10),
  );

  /// "Discuter" : choisir une conversation parmi les personnes de cette
  /// liste qui ont déjà un compte (les autres ne peuvent pas discuter
  /// dans l'app). Accès contextuel à ce Swend, pas une messagerie.
  Future<void> _choisirConversation(
    BuildContext context,
    List<Remplacant> remplacants,
  ) async {
    final surSwend = remplacants
        .where((r) => r.profilId != null && r.id != null)
        .toList();
    final choisi = await showModalBottomSheet<Remplacant>(
      context: context,
      backgroundColor: AppColors.background,
      builder: (feuille) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                fige ? 'Relire la conversation avec…' : 'Discuter avec…',
                style: Theme.of(feuille).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (surSwend.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Aucune personne de votre liste n'est encore sur Swend. "
                    'Vous pouvez les inviter depuis « Modifier ma liste ».',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                )
              else
                for (final r in surSwend)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.chat_bubble_outline, size: 20),
                    title: Text(r.nomComplet),
                    onTap: () => Navigator.pop(feuille, r),
                  ),
            ],
          ),
        ),
      ),
    );
    if (choisi != null && context.mounted) _ouvrirChat(context, choisi);
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
