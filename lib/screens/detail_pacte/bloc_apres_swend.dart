import 'package:flutter/material.dart';

import '../../models/chat_apres_swend.dart';
import '../../theme/app_theme.dart';

/// Fiche d'un Swend passé, une fois le chat après le Swend ouvert (D-023b) :
/// révélation du remplacement, accès au chat (« Discuter », « David vous a
/// écrit »), participants, et « Faire un nouveau Swend » sous l'accès au
/// chat (D-023c). Chat fermé par un nouveau Swend : « Voir la
/// conversation » et « Conversation fermée », plus de création. Jamais avant
/// l'ouverture, jamais sur un Swend annulé (la base n'ouvre pas de chat).
class BlocApresSwend extends StatelessWidget {
  final ChatApresSwend chat;
  final VoidCallback onOuvrir;

  /// « Faire un nouveau Swend » (chat ouvert seulement) ; null : pas de
  /// bouton.
  final VoidCallback? onNouveauSwend;

  const BlocApresSwend({
    super.key,
    required this.chat,
    required this.onOuvrir,
    this.onNouveauSwend,
  });

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
            if (chat.ferme) ...[
              const SizedBox(height: 10),
              const Text(
                titreConversationFermee,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                texteChatFermeNouveauSwend.replaceAll('\n', ' '),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.texteAttenue,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: chat.ferme
                  ? OutlinedButton.icon(
                      onPressed: onOuvrir,
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: Text(chat.libelleFiche),
                    )
                  : FilledButton.icon(
                      onPressed: onOuvrir,
                      icon: Icon(
                        nonLu ? Icons.circle : Icons.forum_outlined,
                        size: nonLu ? 9 : 16,
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
            if (chat.peutFaireNouveauSwend && onNouveauSwend != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onNouveauSwend,
                  child: const Text(libelleNouveauSwend),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
