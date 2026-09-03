import 'package:flutter/material.dart';

import '../../services/contact_repository.dart';
import '../../theme/app_theme.dart';

/// Formulaire de suggestion de restaurant. Accessible depuis le sous-menu
/// "Nous contacter" ou directement depuis l'étape "Où et quand ?" de la
/// création de pacte — dans les deux cas, le bouton retour standard de
/// l'AppBar ramène simplement à l'écran qui a ouvert celui-ci.
class SuggestionRestaurantScreen extends StatefulWidget {
  const SuggestionRestaurantScreen({super.key});

  @override
  State<SuggestionRestaurantScreen> createState() => _SuggestionRestaurantScreenState();
}

class _SuggestionRestaurantScreenState extends State<SuggestionRestaurantScreen> {
  final nomController = TextEditingController();
  final lienController = TextEditingController();
  bool enCours = false;
  String? erreur;
  bool envoye = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Suggestion d'un restaurant")),
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
          const Text('Merci, ta suggestion a bien été envoyée !', textAlign: TextAlign.center),
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
          controller: nomController,
          decoration: const InputDecoration(labelText: 'Nom du restaurant'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: lienController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Lien (optionnel)'),
        ),
        const SizedBox(height: 20),
        if (erreur != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(erreur!, style: const TextStyle(color: AppColors.erreur)),
          ),
        ],
        FilledButton(
          onPressed: !enCours && nomController.text.trim().isNotEmpty ? _envoyer : null,
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
      await ContactRepository.suggererRestaurant(
        nom: nomController.text,
        lien: lienController.text.trim().isEmpty ? null : lienController.text,
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
        erreur = "Impossible d'envoyer ta suggestion pour le moment.\n$e";
      });
    }
  }
}
