import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'message_contact_screen.dart';
import 'suggestion_restaurant_screen.dart';

/// Sous-menu "Nous contacter" du hub : suggérer un restaurant ou nous
/// écrire pour autre chose.
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Image.asset('assets/images/logo_mains.png'),
          tooltip: 'Menu principal',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Nous contacter'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _tuile(
              icone: Icons.restaurant_outlined,
              fond: AppColors.pecheClair,
              iconeColor: AppColors.peche,
              label: "Suggestion d'un restaurant",
              sousLabel: 'Propose-nous un restaurant pour tes prochains pactes',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SuggestionRestaurantScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _tuile(
              icone: Icons.mail_outline,
              fond: AppColors.accentClair,
              iconeColor: AppColors.accentFonce,
              label: 'Autres',
              sousLabel: 'Une question, une remarque ? Écris-nous',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MessageContactScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tuile({
    required IconData icone,
    required Color fond,
    required Color iconeColor,
    required String label,
    required String sousLabel,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icone, color: iconeColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(sousLabel,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.texteAttenue)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
