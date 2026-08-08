import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/pacte.dart';
import '../../models/restaurant.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';

class CreerPacteScreen extends StatefulWidget {
  final bool perspectiveMoi;
  const CreerPacteScreen({super.key, required this.perspectiveMoi});

  @override
  State<CreerPacteScreen> createState() => _CreerPacteScreenState();
}

class _CreerPacteScreenState extends State<CreerPacteScreen> {
  TypeRepas type = TypeRepas.diner;
  DateTime? dateChoisie;
  final List<TextEditingController> nomsRestaurants =
      [TextEditingController(text: 'Au père Lapin')];
  final List<TextEditingController> liensRestaurants =
      [TextEditingController(text: 'https://www.auperelapin.com/')];

  @override
  Widget build(BuildContext context) {
    final nomMoi = widget.perspectiveMoi ? 'Moi' : 'Mon ami';
    final nomAutre = widget.perspectiveMoi ? 'Mon ami' : 'Moi';

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau pacte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Initiateur : $nomMoi → destinataire : $nomAutre',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          const Text('Type de repas', style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<TypeRepas>(
            title: const Text('Déjeuner'),
            value: TypeRepas.dejeuner,
            groupValue: type,
            onChanged: (v) => setState(() => type = v!),
          ),
          RadioListTile<TypeRepas>(
            title: const Text('Dîner'),
            value: TypeRepas.diner,
            groupValue: type,
            onChanged: (v) => setState(() => type = v!),
          ),
          const SizedBox(height: 8),
          const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
          ListTile(
            title: Text(dateChoisie == null
                ? 'Choisir une date'
                : 'Date : ${dateChoisie!.day}/${dateChoisie!.month}/${dateChoisie!.year}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 60)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                locale: const Locale('fr', 'FR'),
              );
              if (d != null) setState(() => dateChoisie = d);
            },
          ),
          const SizedBox(height: 16),
          const Text('1 restaurant proposé', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            "D'autres restaurant vont être proposés bientôt",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nomsRestaurants[0],
            decoration: const InputDecoration(labelText: 'Nom du restaurant'),
          ),
          TextField(
            controller: liensRestaurants[0],
            decoration: const InputDecoration(labelText: 'Lien du site (optionnel)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _peutValider() ? _creerPacte : null,
            child: const Text('Envoyer le pacte'),
          ),
        ],
      ),
    );
  }

  bool _peutValider() {
    if (dateChoisie == null) return false;
    return nomsRestaurants.every((c) => c.text.trim().isNotEmpty);
  }

  void _creerPacte() {
    final date = dateChoisie;

    final restaurants = [
      Restaurant(
        nom: nomsRestaurants[0].text.trim(),
        lien: liensRestaurants[0].text.trim(),
      ),
    ];

    final utilisateurMoi = AppStore.utilisateurCourant(widget.perspectiveMoi);
    final utilisateurAutre = AppStore.utilisateurAutre(widget.perspectiveMoi);

    final pacte = Pacte(
      id: AppStore.nouvelId(),
      type: type,
      date: date,
      dateAutomatique: false,
      restaurantsProposes: restaurants,
      initiateur: CotePacte(
        nomTitulaire: utilisateurMoi.nom,
        listeRemplacants: utilisateurMoi.remplacants,
      ),
      destinataire: CotePacte(
        nomTitulaire: utilisateurAutre.nom,
        listeRemplacants: utilisateurAutre.remplacants,
      ),
    );

    AppStore.pactes.add(pacte);
    Navigator.pop(context);
  }
}
