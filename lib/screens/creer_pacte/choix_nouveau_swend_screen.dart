import 'package:flutter/material.dart';

import '../../models/chat_apres_swend.dart';
import '../../theme/app_theme.dart';

/// Chat à 3 : « Avec qui veux-tu faire un nouveau Swend ? ». Seulement les
/// deux autres personnes, au même niveau (aucun rôle affiché), sans
/// recherche ni ajout ni bouton « Continuer » : toucher une personne
/// disponible mène à « Quand et où ? ». Une personne avec qui un Swend est
/// déjà en cours est grisée.
class ChoixNouveauSwendScreen extends StatelessWidget {
  final List<OptionNouveauSwend> options;

  /// Ouvre la création avec cette personne ; `true` si un Swend a été créé.
  final Future<bool> Function(OptionNouveauSwend) onChoisir;

  const ChoixNouveauSwendScreen({
    super.key,
    required this.options,
    required this.onChoisir,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau Swend')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            titreChoixNouveauSwend,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          for (final o in options) ...[
            _CartePersonne(
              option: o,
              onChoisir: () async {
                final cree = await onChoisir(o);
                if (cree && context.mounted) Navigator.pop(context, true);
              },
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CartePersonne extends StatelessWidget {
  final OptionNouveauSwend option;
  final VoidCallback onChoisir;

  const _CartePersonne({required this.option, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    final disponible = !option.dejaEnCours;
    return Opacity(
      opacity: disponible ? 1 : 0.55,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disponible ? onChoisir : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.prenom,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (!disponible) ...[
                        const SizedBox(height: 4),
                        Text(
                          texteSwendDejaEnCoursAvec(option.prenom),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.texteAttenue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (disponible)
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.texteAttenue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
