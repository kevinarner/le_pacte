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
  bool dateAutomatique = true;
  DateTime? dateChoisie;
  final List<TextEditingController> nomsRestaurants =
      List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> liensRestaurants =
      List.generate(3, (_) => TextEditingController());

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
          SwitchListTile(
            title: const Text("Laisser l'application choisir la date"),
            value: dateAutomatique,
            onChanged: (v) => setState(() => dateAutomatique = v),
          ),
          if (!dateAutomatique)
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
                );
                if (d != null) setState(() => dateChoisie = d);
              },
            ),
          const SizedBox(height: 16),
          const Text('3 restaurants proposés', style: TextStyle(fontWeight: FontWeight.bold)),
          for (int i = 0; i < 3; i++) ...[
            const SizedBox(height: 8),
            TextField(
              controller: nomsRestaurants[i],
              decoration: InputDecoration(labelText: 'Nom du restaurant ${i + 1}'),
            ),
            TextField(
              controller: liensRestaurants[i],
              decoration: const InputDecoration(labelText: 'Lien du site (optionnel)'),
            ),
          ],
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
    if (!dateAutomatique && dateChoisie == null) return false;
    return nomsRestaurants.every((c) => c.text.trim().isNotEmpty);
  }

  void _creerPacte() {
    final date = dateAutomatique
        ? DateTime.now().add(Duration(days: 45 + (DateTime.now().millisecond % 30)))
        : dateChoisie;

    final restaurants = List.generate(
      3,
      (i) => Restaurant(
        nom: nomsRestaurants[i].text.trim(),
        lien: liensRestaurants[i].text.trim(),
      ),
    );

    final nomMoi = widget.perspectiveMoi ? 'Moi' : 'Mon ami';
    final nomAutre = widget.perspectiveMoi ? 'Mon ami' : 'Moi';
    final remplacantsMoi = widget.perspectiveMoi ? AppStore.remplacantsMoi : AppStore.remplacantsAmi;
    final remplacantsAutre = widget.perspectiveMoi ? AppStore.remplacantsAmi : AppStore.remplacantsMoi;

    final pacte = Pacte(
      id: AppStore.nouvelId(),
      type: type,
      date: date,
      dateAutomatique: dateAutomatique,
      restaurantsProposes: restaurants,
      initiateur: CotePacte(nomTitulaire: nomMoi, listeRemplacants: remplacantsMoi),
      destinataire: CotePacte(nomTitulaire: nomAutre, listeRemplacants: remplacantsAutre),
    );

    AppStore.pactes.add(pacte);
    Navigator.pop(context);
  }
}
