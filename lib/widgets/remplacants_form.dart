import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/remplacant.dart';
import '../models/type_repas.dart';
import '../services/contact_picker_service.dart';
import '../utils/noms.dart';
import '../utils/telephone.dart';
import 'envoi_invitation.dart';

/// Formulaire de saisie d'une liste de remplaçants, propre à un pacte.
/// Mute directement [remplacants] (ajout/suppression/édition).
class RemplacantsForm extends StatefulWidget {
  final List<Remplacant> remplacants;
  final VoidCallback onChanged;
  final int minimum;

  /// Nombre maximum de remplaçants par côté du pacte.
  static const int maximum = 5;

  /// Contexte du pacte, utilisé pour rédiger le message d'invitation.
  final String nomAutrePartie;
  final TypeRepas type;
  final List<DateTime> dates;

  /// Numéros (forme E.164) qui ne peuvent pas être ajoutés ici, avec le
  /// message à afficher : le sien, celui de l'autre participant, ou une
  /// personne déjà enregistrée. La base refuse de toute façon ces cas ;
  /// ceci ne sert qu'à le dire tout de suite.
  final Map<String, String> telephonesInterdits;

  const RemplacantsForm({
    super.key,
    required this.remplacants,
    required this.onChanged,
    required this.nomAutrePartie,
    required this.type,
    required this.dates,
    this.minimum = 2,
    this.telephonesInterdits = const {},
  });

  /// Le problème du numéro de [r] dans [liste], ou null s'il est
  /// utilisable (ou pas encore saisi).
  static String? erreurTelephone(
    Remplacant r,
    List<Remplacant> liste,
    Map<String, String> interdits,
  ) {
    if (r.telephone.trim().isEmpty) return null;
    final e164 = normaliserTelephone(r.telephone);
    if (e164 == null) return messageTelephoneInvalide;
    final interdit = interdits[e164];
    if (interdit != null) return interdit;
    final premier = liste.firstWhere(
      (x) => normaliserTelephone(x.telephone) == e164,
    );
    if (!identical(premier, r)) return 'Cette personne est déjà dans la liste.';
    return null;
  }

  /// Vrai si toutes les personnes complètes de [liste] ont un numéro
  /// utilisable.
  static bool listeValide(
    List<Remplacant> liste,
    Map<String, String> interdits,
  ) => liste
      .where((r) => r.estRempli)
      .every((r) => erreurTelephone(r, liste, interdits) == null);

  @override
  State<RemplacantsForm> createState() => _RemplacantsFormState();
}

class _RemplacantsFormState extends State<RemplacantsForm> {
  final Map<Remplacant, TextEditingController> _prenomControllers = {};
  final Map<Remplacant, TextEditingController> _nomControllers = {};
  final Map<Remplacant, TextEditingController> _telControllers = {};

  @override
  void initState() {
    super.initState();
    while (widget.remplacants.length < widget.minimum) {
      widget.remplacants.add(Remplacant());
    }
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
            decoration: InputDecoration(
              labelText: 'Numéro de mobile',
              errorText: RemplacantsForm.erreurTelephone(
                r,
                widget.remplacants,
                widget.telephonesInterdits,
              ),
              errorMaxLines: 2,
            ),
            onChanged: (v) {
              setState(() => r.telephone = v);
              widget.onChanged();
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
          const Text(
            "Cette personne n'a pas encore Swend ?",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                inviterPersonneDeConfiance(context, r, widget.nomAutrePartie),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text("Envoyer l'invitation"),
          ),
        ],
      ),
    );
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

}

/// Invitation générique d'une personne de confiance (préparation, sans
/// demande de remplacement réelle), par Messages ou WhatsApp.
Future<void> inviterPersonneDeConfiance(
  BuildContext context,
  Remplacant r,
  String nomAutrePartie,
) async {
  if (r.telephone.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Renseigne le numéro pour envoyer l'invitation."),
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
  await envoyerInvitation(context, telephone: r.telephone, message: message);
}
