import 'package:flutter/material.dart';

import '../../services/contact_repository.dart';
import '../../theme/app_theme.dart';

/// Formulaire de contact générique ("Autres"). Les messages sont pour
/// l'instant uniquement stockés dans Supabase — l'envoi d'un vrai mail
/// vers une boîte de contact viendra une fois celle-ci créée.
class MessageContactScreen extends StatefulWidget {
  const MessageContactScreen({super.key});

  @override
  State<MessageContactScreen> createState() => _MessageContactScreenState();
}

class _MessageContactScreenState extends State<MessageContactScreen> {
  final objetController = TextEditingController();
  final messageController = TextEditingController();
  bool enCours = false;
  String? erreur;
  bool envoye = false;

  bool get _peutEnvoyer =>
      objetController.text.trim().isNotEmpty && messageController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Autres')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: envoye ? _confirmation() : _formulaire(),
      ),
    );
  }

  Widget _confirmation() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.accent, size: 40),
          const SizedBox(height: 12),
          const Text('Merci, ton message a bien été envoyé !', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
        ],
      ),
    );
  }

  Widget _formulaire() {
    return ListView(
      children: [
        TextField(
          controller: objetController,
          decoration: const InputDecoration(labelText: 'Objet'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: messageController,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        if (erreur != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(erreur!, style: const TextStyle(color: AppColors.erreur)),
          ),
        ],
        FilledButton(
          onPressed: !enCours && _peutEnvoyer ? _envoyer : null,
          child: enCours
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Envoyer'),
        ),
      ],
    );
  }

  Future<void> _envoyer() async {
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      await ContactRepository.envoyerMessageContact(
        objet: objetController.text,
        message: messageController.text,
      );
      if (!mounted) return;
      setState(() {
        enCours = false;
        envoye = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = "Impossible d'envoyer ton message pour le moment.\n$e";
      });
    }
  }
}
