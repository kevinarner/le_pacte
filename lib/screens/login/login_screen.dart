import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_avatar.dart';
import '../root/root_shell.dart';

/// Écran de connexion / inscription (mock — pas de vrai backend : la
/// connexion accepte n'importe quelle saisie, mais l'inscription
/// enregistre vraiment les informations saisies dans le compte "Moi").
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool modeInscription = false;

  // Connexion
  final emailController = TextEditingController();
  final motDePasseController = TextEditingController();

  // Inscription
  final prenomController = TextEditingController();
  final nomController = TextEditingController();
  final telephoneController = TextEditingController();
  final emailInscriptionController = TextEditingController();
  final motDePasseInscriptionController = TextEditingController();
  final confirmationMotDePasseController = TextEditingController();
  Uint8List? photoInscription;

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
                if (modeInscription) _formulaireInscription() else _formulaireConnexion(),
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

  Widget _formulaireConnexion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _champ('Adresse email', 'toi@exemple.com', emailController),
        const SizedBox(height: 12),
        _champ('Mot de passe', '••••••••', motDePasseController, masque: true),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _seConnecter,
          child: const Text('Se connecter'),
        ),
      ],
    );
  }

  Widget _formulaireInscription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: PhotoAvatar(
            photo: photoInscription,
            nom: '${prenomController.text} ${nomController.text}',
            taille: 76,
            libellePlaceholder: photoInscription == null ? 'Ta photo\n(optionnel)' : null,
            onPhotoChoisie: (octets) => setState(() => photoInscription = octets),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _champ('Prénom', 'Ton prénom', prenomController, onChanged: true),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _champ('Nom', 'Ton nom', nomController, onChanged: true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _champ('Numéro de téléphone', '06 12 34 56 78', telephoneController,
            type: TextInputType.phone, onChanged: true),
        const SizedBox(height: 12),
        _champ('Adresse email', 'toi@exemple.com', emailInscriptionController,
            type: TextInputType.emailAddress, onChanged: true),
        const SizedBox(height: 12),
        _champ('Mot de passe', '••••••••', motDePasseInscriptionController,
            masque: true, onChanged: true),
        const SizedBox(height: 12),
        _champ('Confirmer le mot de passe', '••••••••', confirmationMotDePasseController,
            masque: true, onChanged: true),
        const SizedBox(height: 16),
        if (_erreursInscription().isNotEmpty) ...[
          for (final erreur in _erreursInscription())
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: AppColors.terracotta),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(erreur,
                        style: const TextStyle(fontSize: 12, color: AppColors.terracotta)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: _peutCreerCompte() ? _creerCompte : null,
          child: const Text('Créer mon compte'),
        ),
      ],
    );
  }

  Widget _champ(String label, String placeholder, TextEditingController controller,
      {bool masque = false, TextInputType? type, bool onChanged = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: masque,
          keyboardType: type,
          decoration: InputDecoration(hintText: placeholder),
          onChanged: onChanged ? (_) => setState(() {}) : null,
        ),
      ],
    );
  }

  List<String> _erreursInscription() {
    final erreurs = <String>[];
    if (prenomController.text.trim().isEmpty || nomController.text.trim().isEmpty) {
      erreurs.add('Renseigne ton prénom et ton nom.');
    }
    if (telephoneController.text.trim().isEmpty) {
      erreurs.add('Renseigne ton numéro de téléphone.');
    }
    if (emailInscriptionController.text.trim().isEmpty) {
      erreurs.add('Renseigne ton adresse email.');
    }
    if (motDePasseInscriptionController.text.isEmpty) {
      erreurs.add('Choisis un mot de passe.');
    } else if (motDePasseInscriptionController.text != confirmationMotDePasseController.text) {
      erreurs.add('Les deux mots de passe ne correspondent pas.');
    }
    return erreurs;
  }

  bool _peutCreerCompte() => _erreursInscription().isEmpty;

  void _seConnecter() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }

  void _creerCompte() {
    final moi = AppStore.moi;
    moi.prenom = prenomController.text.trim();
    moi.nom = nomController.text.trim();
    moi.telephone = telephoneController.text.trim();
    moi.email = emailInscriptionController.text.trim();
    if (photoInscription != null) {
      moi.photo = photoInscription;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }
}
