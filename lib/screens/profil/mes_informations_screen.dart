import 'package:flutter/material.dart';

import '../../services/app_store.dart';
import '../../services/profil_repository.dart';
import '../../theme/app_theme.dart';

/// Détail des informations de compte : Nom (non modifiable ici), puis
/// Téléphone / Email / Mot de passe, chacun avec un bouton "Modifier" qui
/// persiste réellement le changement dans Supabase.
class MesInformationsScreen extends StatefulWidget {
  const MesInformationsScreen({super.key});

  @override
  State<MesInformationsScreen> createState() => _MesInformationsScreenState();
}

class _MesInformationsScreenState extends State<MesInformationsScreen> {
  @override
  Widget build(BuildContext context) {
    final utilisateur = AppStore.moi;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes informations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                _ligne('Nom', utilisateur.nomComplet),
                _separateur(),
                _ligne('Téléphone', utilisateur.telephone, onModifier: _modifierTelephone),
                _separateur(),
                _ligne('Email', utilisateur.email, onModifier: _modifierEmail),
                _separateur(),
                _ligne('Mot de passe', '••••••••', onModifier: _modifierMotDePasse),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _separateur() => const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _ligne(String label, String valeur, {VoidCallback? onModifier}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.texteAttenue)),
                const SizedBox(height: 2),
                Text(
                  valeur.isEmpty ? '—' : valeur,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (onModifier != null)
            TextButton(onPressed: onModifier, child: const Text('Modifier')),
        ],
      ),
    );
  }

  Future<void> _modifierTelephone() async {
    final valeur = await _dialogueChampUnique(
      titre: 'Modifier le téléphone',
      labelChamp: 'Numéro de téléphone',
      valeurInitiale: AppStore.moi.telephone,
      clavier: TextInputType.phone,
      messageErreur: (e) {
        final bas = e.toLowerCase();
        if (bas.contains('telephone') && (bas.contains('duplicate') || bas.contains('unique'))) {
          return 'Ce numéro de téléphone est déjà associé à un autre compte.';
        }
        return 'Impossible de mettre à jour le téléphone pour le moment.';
      },
      enregistrer: ProfilRepository.modifierTelephone,
    );
    if (valeur == null || !mounted) return;
    setState(() => AppStore.moi.telephone = valeur.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Numéro de téléphone mis à jour.')),
    );
  }

  Future<void> _modifierEmail() async {
    final valeur = await _dialogueChampUnique(
      titre: "Modifier l'email",
      labelChamp: 'Adresse email',
      valeurInitiale: AppStore.moi.email,
      clavier: TextInputType.emailAddress,
      messageErreur: (_) => "Impossible de mettre à jour l'email pour le moment.",
      enregistrer: ProfilRepository.modifierEmail,
    );
    if (valeur == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Un email de confirmation a été envoyé à $valeur. '
            'Ta nouvelle adresse sera active une fois ce lien cliqué.'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _modifierMotDePasse() async {
    final nouveau = await showDialog<String>(
      context: context,
      builder: (context) => _DialogueMotDePasse(),
    );
    if (nouveau == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mot de passe mis à jour.')),
    );
  }

  /// Dialogue générique à un seul champ texte : renvoie la nouvelle
  /// valeur si elle a bien été enregistrée côté serveur, sinon null si
  /// l'utilisateur a annulé.
  Future<String?> _dialogueChampUnique({
    required String titre,
    required String labelChamp,
    required String valeurInitiale,
    required TextInputType clavier,
    required String Function(String) messageErreur,
    required Future<void> Function(String) enregistrer,
  }) {
    final controller = TextEditingController(text: valeurInitiale);
    return showDialog<String>(
      context: context,
      builder: (context) => _DialogueChampUnique(
        titre: titre,
        labelChamp: labelChamp,
        controller: controller,
        clavier: clavier,
        messageErreur: messageErreur,
        enregistrer: enregistrer,
      ),
    );
  }
}

class _DialogueChampUnique extends StatefulWidget {
  final String titre;
  final String labelChamp;
  final TextEditingController controller;
  final TextInputType clavier;
  final String Function(String) messageErreur;
  final Future<void> Function(String) enregistrer;

  const _DialogueChampUnique({
    required this.titre,
    required this.labelChamp,
    required this.controller,
    required this.clavier,
    required this.messageErreur,
    required this.enregistrer,
  });

  @override
  State<_DialogueChampUnique> createState() => _DialogueChampUniqueState();
}

class _DialogueChampUniqueState extends State<_DialogueChampUnique> {
  bool enCours = false;
  String? erreur;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            keyboardType: widget.clavier,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.labelChamp),
          ),
          if (erreur != null) ...[
            const SizedBox(height: 8),
            Text(erreur!, style: const TextStyle(color: AppColors.erreur, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: enCours ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: enCours ? null : _enregistrer,
          child: enCours
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final valeur = widget.controller.text.trim();
    if (valeur.isEmpty) {
      setState(() => erreur = 'Ce champ ne peut pas être vide.');
      return;
    }
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      await widget.enregistrer(valeur);
      if (!mounted) return;
      Navigator.pop(context, valeur);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = widget.messageErreur(e.toString());
      });
    }
  }
}

class _DialogueMotDePasse extends StatefulWidget {
  @override
  State<_DialogueMotDePasse> createState() => _DialogueMotDePasseState();
}

class _DialogueMotDePasseState extends State<_DialogueMotDePasse> {
  final nouveauController = TextEditingController();
  final confirmationController = TextEditingController();
  bool enCours = false;
  String? erreur;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le mot de passe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nouveauController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nouveau mot de passe'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: confirmationController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirme le mot de passe'),
          ),
          if (erreur != null) ...[
            const SizedBox(height: 8),
            Text(erreur!, style: const TextStyle(color: AppColors.erreur, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: enCours ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: enCours ? null : _enregistrer,
          child: enCours
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }

  Future<void> _enregistrer() async {
    final nouveau = nouveauController.text;
    if (nouveau.length < 6) {
      setState(() => erreur = 'Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }
    if (nouveau != confirmationController.text) {
      setState(() => erreur = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      await ProfilRepository.modifierMotDePasse(nouveau);
      if (!mounted) return;
      Navigator.pop(context, nouveau);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = 'Impossible de mettre à jour le mot de passe pour le moment.';
      });
    }
  }
}
