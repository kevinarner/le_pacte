import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants.dart';
import '../../models/utilisateur.dart';
import '../../services/app_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_avatar.dart';
import '../root/root_shell.dart';

/// Écran de connexion / inscription, branché sur Supabase Auth.
/// La photo choisie à l'inscription n'est pas encore envoyée au
/// serveur (le stockage des fichiers n'est pas encore configuré) —
/// elle reste locale à cette session pour l'instant.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool modeInscription = false;
  bool enCours = false;
  String? erreur;
  bool inscriptionEnAttenteConfirmation = false;

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

  SupabaseClient get _supabase => Supabase.instance.client;

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
                if (inscriptionEnAttenteConfirmation)
                  _messageConfirmationEnvoyee()
                else if (modeInscription)
                  _formulaireInscription()
                else
                  _formulaireConnexion(),
                if (!inscriptionEnAttenteConfirmation) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: enCours
                        ? null
                        : () => setState(() {
                              modeInscription = !modeInscription;
                              erreur = null;
                            }),
                    child: Text(
                      modeInscription
                          ? 'Déjà un compte ? Se connecter'
                          : "Pas encore de compte ? Créer un compte",
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageConfirmationEnvoyee() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 40, color: AppColors.terracotta),
        const SizedBox(height: 12),
        Text(
          "Un email de confirmation a été envoyé à ${emailInscriptionController.text.trim()}. "
          "Clique sur le lien reçu, puis connecte-toi.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => setState(() {
            inscriptionEnAttenteConfirmation = false;
            modeInscription = false;
          }),
          child: const Text('Aller à la connexion'),
        ),
      ],
    );
  }

  Widget _formulaireConnexion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _champ('Adresse email', 'toi@exemple.com', emailController,
            type: TextInputType.emailAddress, onChanged: true),
        const SizedBox(height: 12),
        _champ('Mot de passe', '••••••••', motDePasseController, masque: true, onChanged: true),
        const SizedBox(height: 16),
        if (_erreursConnexion().isNotEmpty) ...[
          for (final e in _erreursConnexion())
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: AppColors.terracotta),
                  const SizedBox(width: 6),
                  Expanded(
                    child:
                        Text(e, style: const TextStyle(fontSize: 12, color: AppColors.terracotta)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (erreur != null) _messageErreurWidget(),
        FilledButton(
          onPressed: (enCours || _erreursConnexion().isNotEmpty) ? null : _seConnecter,
          child: enCours
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Se connecter'),
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
          for (final e in _erreursInscription())
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: AppColors.terracotta),
                  const SizedBox(width: 6),
                  Expanded(
                    child:
                        Text(e, style: const TextStyle(fontSize: 12, color: AppColors.terracotta)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (erreur != null) _messageErreurWidget(),
        FilledButton(
          onPressed: (_peutCreerCompte() && !enCours) ? _creerCompte : null,
          child: enCours
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Créer mon compte'),
        ),
      ],
    );
  }

  Widget _messageErreurWidget() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.terracotta),
          const SizedBox(width: 6),
          Expanded(
            child: Text(erreur!, style: const TextStyle(fontSize: 12, color: AppColors.terracotta)),
          ),
        ],
      ),
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

  List<String> _erreursConnexion() {
    final erreurs = <String>[];
    if (emailController.text.trim().isEmpty) {
      erreurs.add('Renseigne ton adresse email.');
    }
    if (motDePasseController.text.isEmpty) {
      erreurs.add('Renseigne ton mot de passe.');
    }
    return erreurs;
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
    } else if (motDePasseInscriptionController.text.length < 6) {
      erreurs.add('Le mot de passe doit contenir au moins 6 caractères.');
    } else if (motDePasseInscriptionController.text != confirmationMotDePasseController.text) {
      erreurs.add('Les deux mots de passe ne correspondent pas.');
    }
    return erreurs;
  }

  bool _peutCreerCompte() => _erreursInscription().isEmpty;

  String _messageAuth(AuthException e) {
    switch (e.message) {
      case 'Invalid login credentials':
        return 'Email ou mot de passe incorrect.';
      case 'Email not confirmed':
        return "Confirme ton adresse email avant de te connecter (vérifie tes emails).";
      case 'User already registered':
        return 'Un compte existe déjà avec cette adresse email.';
      case 'missing email or phone':
        return "Renseigne ton adresse email.";
      default:
        return e.message;
    }
  }

  Future<void> _seConnecter() async {
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      final reponse = await _supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: motDePasseController.text,
      );
      await _chargerProfilEtEntrer(reponse.user!.id);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = _messageAuth(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = 'Impossible de joindre le serveur pour le moment. Réessaie.';
      });
    }
  }

  Future<void> _creerCompte() async {
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      final reponse = await _supabase.auth.signUp(
        email: emailInscriptionController.text.trim(),
        password: motDePasseInscriptionController.text,
        emailRedirectTo: lienTelechargementApp,
        data: {
          'prenom': prenomController.text.trim(),
          'nom': nomController.text.trim(),
          'telephone': telephoneController.text.trim(),
        },
      );
      if (reponse.session != null) {
        await _chargerProfilEtEntrer(reponse.user!.id);
      } else {
        if (!mounted) return;
        setState(() {
          enCours = false;
          inscriptionEnAttenteConfirmation = true;
        });
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = _messageAuth(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = 'Impossible de joindre le serveur pour le moment. Réessaie.';
      });
    }
  }

  Future<void> _chargerProfilEtEntrer(String userId) async {
    try {
      final profil = await _supabase.from('profiles').select().eq('id', userId).single();
      AppStore.moi = Utilisateur(
        id: userId,
        prenom: profil['prenom'] as String? ?? '',
        nom: profil['nom'] as String? ?? '',
        telephone: profil['telephone'] as String? ?? '',
        email: profil['email'] as String? ?? '',
      );
    } catch (_) {
      AppStore.moi = Utilisateur(id: userId, email: emailController.text.trim());
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RootShell()),
    );
  }
}
