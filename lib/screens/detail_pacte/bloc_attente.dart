import 'package:flutter/material.dart';

/// Bloc affiché quand ce n'est pas mon tour d'agir : le pacte est en
/// cours de négociation mais on attend une action de l'autre partie.
class BlocAttente extends StatelessWidget {
  final String texte;
  const BlocAttente({super.key, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, size: 20, color: Colors.black45),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texte, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
