import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/telephone.dart';

enum CanalEnvoi { messages, whatsapp }

/// Propose d'envoyer un message prérempli par Messages ou par WhatsApp,
/// au numéro canonique (E.164). Le canal n'est qu'un moyen d'envoi : il
/// ne dit rien de l'existence d'un compte Swend, et le texte est le même
/// quel que soit le canal.
Future<void> envoyerInvitation(
  BuildContext context, {
  required String telephone,
  required String message,
  String titre = "Envoyer l'invitation",
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final e164 = normaliserTelephone(telephone);
  if (e164 == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text(messageTelephoneInvalide)),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    builder: (feuille) => _ChoixCanal(
      titre: titre,
      // L'ouverture part directement du geste de l'utilisateur (sinon
      // certains navigateurs bloquent l'ouverture de l'app).
      onChoix: (canal) {
        Navigator.pop(feuille);
        _ouvrir(canal, e164, message, messenger);
      },
    ),
  );
}

Future<void> _ouvrir(
  CanalEnvoi canal,
  String e164,
  String message,
  ScaffoldMessengerState messenger,
) async {
  final texte = Uri.encodeComponent(message);
  if (canal == CanalEnvoi.messages) {
    final ok = await _essayer(Uri.parse('sms:$e164?body=$texte'));
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Impossible d'ouvrir Messages sur cet appareil."),
        ),
      );
    }
    return;
  }
  final ok = await _essayer(
    Uri.parse('https://wa.me/${e164.substring(1)}?text=$texte'),
    externe: true,
  );
  if (!ok) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text("WhatsApp n'a pas pu s'ouvrir."),
        action: SnackBarAction(
          label: 'Utiliser Messages',
          onPressed: () =>
              _ouvrir(CanalEnvoi.messages, e164, message, messenger),
        ),
      ),
    );
  }
}

Future<bool> _essayer(Uri uri, {bool externe = false}) async {
  try {
    return await launchUrl(
      uri,
      mode: externe ? LaunchMode.externalApplication : LaunchMode.platformDefault,
      webOnlyWindowName: externe ? '_blank' : null,
    );
  } catch (_) {
    return false;
  }
}

class _ChoixCanal extends StatelessWidget {
  final String titre;
  final void Function(CanalEnvoi) onChoix;

  const _ChoixCanal({required this.titre, required this.onChoix});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titre, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Le message est prérempli, il pourra être relu avant l\'envoi.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => onChoix(CanalEnvoi.messages),
              icon: const Icon(Icons.sms_outlined, size: 20),
              label: const Text('Messages'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => onChoix(CanalEnvoi.whatsapp),
              icon: const Icon(Icons.chat_outlined, size: 20),
              label: const Text('WhatsApp'),
            ),
          ],
        ),
      ),
    );
  }
}
