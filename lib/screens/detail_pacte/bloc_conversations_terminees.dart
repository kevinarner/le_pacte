import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/gel_swend.dart';
import '../../models/remplacant.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';

/// « En cas d'imprévu » une fois le Swend passé ou annulé (D-023a), côté
/// titulaire : plus aucune action de gestion, seulement la relecture des
/// conversations qui ont eu une activité (message ou événement) — en lecture
/// seule. Une seule conversation : ouverte directement ; plusieurs : choix.
/// Rien du tout s'il n'y a ni remplacement à rappeler ni conversation à relire.
class BlocConversationsTerminees extends StatefulWidget {
  final CotePacte monCote;

  /// Swend passé (pas annulé) : on rappelle qui a pris la place, s'il y en a
  /// une. Pour un Swend annulé, ce rappel n'a plus de sens.
  final bool rappelerRemplacement;

  const BlocConversationsTerminees({
    super.key,
    required this.monCote,
    required this.rappelerRemplacement,
  });

  @override
  State<BlocConversationsTerminees> createState() =>
      _BlocConversationsTermineesState();
}

class _BlocConversationsTermineesState
    extends State<BlocConversationsTerminees> {
  List<Remplacant>? _aRelire;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final fiches = widget.monCote.listeRemplacants.where((r) => r.id != null);
    Set<String> actifs;
    try {
      actifs = await PacteRepository.filsAvecActivite([
        for (final r in fiches) r.id!,
      ]);
    } catch (_) {
      actifs = {};
    }
    if (!mounted) return;
    setState(() => _aRelire = filsARelire(fiches, actifs));
  }

  @override
  Widget build(BuildContext context) {
    final aRelire = _aRelire;
    final designe = widget.rappelerRemplacement
        ? widget.monCote.listeRemplacants
              .where((r) => r.selectionne)
              .firstOrNull
        : null;
    if (designe == null && (aRelire == null || aRelire.isEmpty)) {
      return const SizedBox.shrink();
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
                '${designe.prenom} a pris votre place',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (aRelire != null && aRelire.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _relire(context, aRelire),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('Relire une conversation'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _relire(BuildContext context, List<Remplacant> aRelire) async {
    final choisi = aRelire.length == 1
        ? aRelire.first
        : await showModalBottomSheet<Remplacant>(
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
                      'Relire la conversation avec…',
                      style: Theme.of(feuille).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (final r in aRelire)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.chat_bubble_outline,
                          size: 20,
                        ),
                        title: Text(r.nomComplet),
                        onTap: () => Navigator.pop(feuille, r),
                      ),
                  ],
                ),
              ),
            ),
          );
    if (choisi == null || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          remplacantId: choisi.id!,
          nomInterlocuteur: choisi.nomComplet,
          telephoneInterlocuteur: choisi.telephone,
        ),
      ),
    );
  }
}
