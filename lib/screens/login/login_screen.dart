import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../root/root_shell.dart';

/// Écran de connexion / inscription (mock — pas de vrai backend, on
/// accepte n'importe quelle saisie et on ouvre le shell principal).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool modeInscription = false;
  final emailController = TextEditingController();
  final motDePasseController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.terracottaClair,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.swap_horiz, color: AppColors.terracotta),
                ),
                const SizedBox(height: 16),
                Text('Le Pacte', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const SizedBox(
                  width: 260,
                  child: Text(
                    "Un rendez-vous fixé loin devant. Aucune nouvelle avant le jour J. "
                    "Et un doute qui vous accompagne jusqu'au bout : qui, vraiment, sera là ?",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 24),
                _champ('Adresse email', 'toi@exemple.com', emailController),
                const SizedBox(height: 12),
                _champ('Mot de passe', '••••••••', motDePasseController, masque: true),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _valider,
                  child: Text(modeInscription ? 'Créer mon compte' : 'Se connecter'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => modeInscription = !modeInscription),
                  child: Text(
                    modeInscription
                        ? 'Déjà un compte ? Se connecter'
                        : "Pas encore de compte ? Créer un compte",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _champ(String label, String placeholder, TextEditingController controller,
      {bool masque = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: masque,
          decoration: InputDecoration(hintText: placeholder),
        ),
      ],
    );
  }

  void _valider() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }
}
