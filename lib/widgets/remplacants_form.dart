import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../models/remplacant.dart';
import '../models/type_repas.dart';
import '../services/contact_picker_service.dart';
import '../services/pacte_repository.dart';
import '../theme/app_theme.dart';
import '../utils/noms.dart';

/// Formulaire de saisie d'une liste de remplaçants, propre à un pacte.
/// Mute directement [remplacants] (ajout/suppression/édition).
class RemplacantsForm extends StatefulWidget {
  final List<Remplacant> remplacants;
  final VoidCallback onChanged;
  final int minimum;

  /// Nombre maximum de remplaçants par côté du pacte.
  static const int maximum = 5;

  /// Contexte du pacte, utilisé pour rédiger le message d'invitation SMS.
  final String nomAutrePartie;
  final TypeRepas type;
  final List<DateTime> dates;

  const RemplacantsForm({
    super.key,
    required this.remplacants,
    required this.onChanged,
    required this.nomAutrePartie,
    required this.type,
    required this.dates,
    this.minimum = 2,
  });

  @override
  State<RemplacantsForm> createState() => _RemplacantsFormState();
}

class _RemplacantsFormState extends State<RemplacantsForm> {
  final Map<Remplacant, TextEditingController> _prenomControllers = {};
  final Map<Remplacant, TextEditingController> _nomControllers = {};
  final Map<Remplacant, TextEditingController> _telControllers = {};

  /// Id du compte Swend de chaque personne, si un numéro déjà tapé y
  /// correspond — absent tant que la vérification n'a rien trouvé.
  final Map<Remplacant, String?> _profilIds = {};
  final Map<Remplacant, Timer> _debounces = {};

  @override
  void initState() {
    super.initState();
    while (widget.remplacants.length < widget.minimum) {
      widget.remplacants.add(Remplacant());
    }
  }

  @override
  void dispose() {
    for (final t in _debounces.values) {
      t.cancel();
    }
    super.dispose();
  }

  TextEditingController _prenomCtrl(Remplacant r) => _prenomControllers
      .putIfAbsent(r, () => TextEditingController(text: r.prenom));

  TextEditingController _nomCtrl(Remplacant r) =>
      _nomControllers.putIfAbsent(r, () => TextEditingController(text: r.nom));

  TextEditingController _telCtrl(Remplacant r) => _telControllers.putIfAbsent(
    r,
    () => TextEditingController(text: r.telephone),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < widget.remplacants.length; i++) _ligne(i),
        const SizedBox(height: 4),
        if (widget.remplacants.length < RemplacantsForm.maximum)
          OutlinedButton.icon(
            onPressed: _ajouter,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une personne'),
          )
        else
          Text(
            'Maximum ${RemplacantsForm.maximum} personnes atteint.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
      ],
    );
  }

  Widget _ligne(int index) {
    final r = widget.remplacants[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Personne ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.remplacants.length > widget.minimum)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() {
                    widget.remplacants.removeAt(index);
                    widget.onChanged();
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _prenomCtrl(r),
                  decoration: const InputDecoration(labelText: 'Prénom'),
                  onChanged: (v) {
                    r.prenom = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _nomCtrl(r),
                  decoration: const InputDecoration(labelText: 'Nom'),
                  onChanged: (v) {
                    r.nom = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _telCtrl(r),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro de téléphone'),
            onChanged: (v) {
              r.telephone = v;
              widget.onChanged();
              _onTelephoneChange(r, v);
            },
          ),
          if (ContactPickerService.disponible) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _choisirDansLesContacts(r),
              icon: const Icon(Icons.contacts_outlined, size: 18),
              label: const Text('Choisir dans mes contacts'),
            ),
          ],
          const SizedBox(height: 8),
          if (_profilIds[r] != null)
            const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: AppColors.accentFonce),
                SizedBox(width: 6),
                Text(
                  'Déjà sur Swend',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.accentFonce,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else ...[
            const Text(
              "Cette personne n'a pas encore Swend ?",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _inviterParSms(r),
              icon: const Icon(Icons.sms_outlined, size: 18),
              label: const Text('Inviter par SMS'),
            ),
          ],
        ],
      ),
    );
  }

  /// Vérifie si ce numéro correspond à un compte Swend existant, avec un
  /// léger délai pour laisser l'utilisateur finir de taper.
  void _onTelephoneChange(Remplacant r, String valeur) {
    setState(() => _profilIds[r] = null);
    _debounces[r]?.cancel();
    final numero = valeur.trim();
    if (numero.length < 6) return;
    _debounces[r] = Timer(const Duration(milliseconds: 500), () async {
      try {
        final id = await PacteRepository.trouverProfilParTelephone(numero);
        if (!mounted || _telCtrl(r).text.trim() != numero) return;
        setState(() => _profilIds[r] = id);
      } catch (_) {
        // Pas grave : le bouton "Inviter par SMS" reste simplement affiché.
      }
    });
  }

  Future<void> _choisirDansLesContacts(Remplacant r) async {
    final contact = await ContactPickerService.choisirContact();
    if (contact == null || !mounted) return;
    final nomComplet = contact['nom'] ?? '';
    final parts = nomComplet.trim().split(RegExp(r'\s+'));
    setState(() {
      if (parts.isNotEmpty && parts.first.isNotEmpty) {
        r.prenom = parts.first;
        r.nom = parts.skip(1).join(' ');
        _prenomCtrl(r).text = r.prenom;
        _nomCtrl(r).text = r.nom;
      }
      final telephone = contact['telephone'] ?? '';
      if (telephone.isNotEmpty) {
        r.telephone = telephone;
        _telCtrl(r).text = telephone;
      }
      widget.onChanged();
    });
  }

  void _ajouter() {
    if (widget.remplacants.length >= RemplacantsForm.maximum) return;
    setState(() {
      widget.remplacants.add(Remplacant());
      widget.onChanged();
    });
  }

  Future<void> _inviterParSms(Remplacant r) =>
      inviterPersonneDeConfianceParSms(context, r, widget.nomAutrePartie);
}

/// SMS d'invitation générique d'une personne de confiance (pas encore
/// sur Swend) — préparation, sans demande de remplacement réelle.
Future<void> inviterPersonneDeConfianceParSms(
  BuildContext context,
  Remplacant r,
  String nomAutrePartie,
) async {
  final numero = r.telephone.trim();
  if (numero.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Renseigne le numéro de téléphone pour inviter par SMS.'),
      ),
    );
    return;
  }
  final prenom = r.prenom.trim();
  final salutation = prenom.isNotEmpty ? 'Hello $prenom' : 'Hello';
  final autreComplet = nomAutrePartie.trim();
  final autre = autreComplet.isNotEmpty ? prenomDe(autreComplet) : 'mon ami';
  final message =
      "$salutation, j'ai proposé un Swend à $autre et j'aimerais pouvoir compter sur toi "
      "en cas d'imprévu.\n"
      "Si finalement je ne peux pas être là et que tu es dispo, tu pourrais prendre ma place. "
      "Ça te dit ?\n"
      "Je te laisse en découvrir plus sur Swend :)\n"
      "$lienTelechargementApp";
  final numeroPropre = numero.replaceAll(RegExp(r'\s+'), '');
  await launchUrl(
    Uri.parse('sms:$numeroPropre?body=${Uri.encodeComponent(message)}'),
  );
}
