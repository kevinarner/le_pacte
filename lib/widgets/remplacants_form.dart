import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../models/remplacant.dart';

/// Formulaire de saisie d'une liste de remplaçants, propre à un pacte.
/// Mute directement [remplacants] (ajout/suppression/édition).
class RemplacantsForm extends StatefulWidget {
  final List<Remplacant> remplacants;
  final VoidCallback onChanged;
  final int minimum;

  const RemplacantsForm({
    super.key,
    required this.remplacants,
    required this.onChanged,
    this.minimum = 2,
  });

  @override
  State<RemplacantsForm> createState() => _RemplacantsFormState();
}

class _RemplacantsFormState extends State<RemplacantsForm> {
  final Map<Remplacant, TextEditingController> _prenomControllers = {};
  final Map<Remplacant, TextEditingController> _nomControllers = {};
  final Map<Remplacant, TextEditingController> _telControllers = {};
  final Map<Remplacant, TextEditingController> _emailControllers = {};

  @override
  void initState() {
    super.initState();
    while (widget.remplacants.length < widget.minimum) {
      widget.remplacants.add(Remplacant());
    }
  }

  TextEditingController _prenomCtrl(Remplacant r) =>
      _prenomControllers.putIfAbsent(r, () => TextEditingController(text: r.prenom));

  TextEditingController _nomCtrl(Remplacant r) =>
      _nomControllers.putIfAbsent(r, () => TextEditingController(text: r.nom));

  TextEditingController _telCtrl(Remplacant r) =>
      _telControllers.putIfAbsent(r, () => TextEditingController(text: r.telephone));

  TextEditingController _emailCtrl(Remplacant r) =>
      _emailControllers.putIfAbsent(r, () => TextEditingController(text: r.email));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < widget.remplacants.length; i++) _ligne(i),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _ajouter,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Ajouter un remplaçant'),
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
                child: Text('Remplaçant ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
            onChanged: (v) => r.telephone = v,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl(r),
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Adresse email (optionnel)'),
            onChanged: (v) => r.email = v,
          ),
          const SizedBox(height: 8),
          const Text(
            "Si cette personne n'a pas encore l'application, invitez-la à la télécharger :",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _inviterParSms(r),
            icon: const Icon(Icons.sms_outlined, size: 18),
            label: const Text('Inviter par SMS'),
          ),
        ],
      ),
    );
  }

  void _ajouter() {
    setState(() {
      widget.remplacants.add(Remplacant());
      widget.onChanged();
    });
  }

  Future<void> _inviterParSms(Remplacant r) async {
    final numero = r.telephone.trim();
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne le numéro de téléphone pour inviter par SMS.')),
      );
      return;
    }
    final prenom = r.prenom.trim();
    final salutation = prenom.isNotEmpty ? 'Salut $prenom' : 'Salut';
    final message = "$salutation, je t'invite à télécharger Le Pacte pour pouvoir me remplacer "
        'si besoin : $lienTelechargementApp';
    await launchUrl(Uri(scheme: 'sms', path: numero, queryParameters: {'body': message}));
  }
}
