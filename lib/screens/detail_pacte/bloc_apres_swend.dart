import 'package:flutter/material.dart';

import '../../models/chat_apres_swend.dart';
import '../../theme/app_theme.dart';

/// Fiche d'un Swend passé, une fois le chat après le Swend ouvert (D-023b) :
/// révélation du remplacement, accès au chat (« Discuter », « David vous a
/// écrit », plus tard « Conversation terminée »), participants. Jamais
/// avant l'ouverture, jamais sur un Swend annulé (la base n'ouvre pas de
/// chat).
class BlocApresSwend extends StatelessWidget {
  final ChatApresSwend chat;
  final VoidCallback onOuvrir;

  const BlocApresSwend({super.key, required this.chat, required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    final revelation = chat.revelation;
    final avecQui = chat.avecQui;
    final nonLu = chat.etat == EtatChatApres.nonLu;
    return Card(
      color: AppColors.pecheClair,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'APRÈS LE SWEND',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.texteAttenue,
                letterSpacing: 0.06,
              ),
            ),
            if (revelation != null) ...[
              const SizedBox(height: 8),
              Text(
                revelation,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: nonLu
                  ? FilledButton.icon(
                      onPressed: onOuvrir,
                      icon: const Icon(Icons.circle, size: 9),
                      label: Text(chat.libelleFiche),
                    )
                  : OutlinedButton.icon(
                      onPressed: onOuvrir,
                      icon: Icon(
                        chat.ferme ? Icons.lock_outline : Icons.forum_outlined,
                        size: 16,
                      ),
                      label: Text(chat.libelleFiche),
                    ),
            ),
            if (avecQui != null) ...[
              const SizedBox(height: 6),
              Text(
                avecQui,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.texteAttenue,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
