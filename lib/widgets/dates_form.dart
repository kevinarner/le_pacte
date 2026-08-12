import 'package:flutter/material.dart';

import '../models/type_repas.dart';
import '../utils/date_fr.dart';

/// Formulaire de saisie d'une liste de dates (avec horaire) proposées
/// pour un pacte. Mute directement [dates] (ajout/suppression/modification).
class DatesForm extends StatefulWidget {
  final List<DateTime> dates;
  final VoidCallback onChanged;
  final TypeRepas type;
  final int minimum;

  const DatesForm({
    super.key,
    required this.dates,
    required this.onChanged,
    required this.type,
    this.minimum = 1,
  });

  @override
  State<DatesForm> createState() => _DatesFormState();
}

class _DatesFormState extends State<DatesForm> {
  @override
  void didUpdateWidget(covariant DatesForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      // Le type de repas a changé : on recale les horaires qui ne sont
      // plus dans la plage autorisée (ex. 20h en passant de dîner à déjeuner).
      final creneaux = creneauxPourType(widget.type);
      for (var i = 0; i < widget.dates.length; i++) {
        if (!creneaux.contains(heureDe(widget.dates[i]))) {
          widget.dates[i] = avecHeure(widget.dates[i], creneaux.first);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < widget.dates.length; i++) _ligne(i),
        OutlinedButton.icon(
          onPressed: _ajouterDate,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Ajouter une date'),
        ),
      ],
    );
  }

  Widget _ligne(int index) {
    final date = widget.dates[index];
    final creneaux = creneauxPourType(widget.type);
    final heureActuelle = creneaux.contains(heureDe(date)) ? heureDe(date) : creneaux.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(formaterDateEnToutesLettres(date)),
            onTap: () => _modifierDate(index),
            trailing: widget.dates.length > widget.minimum
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _retirer(index),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: Colors.black54),
                const SizedBox(width: 8),
                const Text('Horaire :', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                DropdownButton<TimeOfDay>(
                  value: heureActuelle,
                  underline: const SizedBox(),
                  items: [
                    for (final c in creneaux)
                      DropdownMenuItem(value: c, child: Text(formaterHeure(c))),
                  ],
                  onChanged: (h) {
                    if (h == null) return;
                    setState(() {
                      widget.dates[index] = avecHeure(date, h);
                      widget.onChanged();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _ajouterDate() async {
    final d = await _choisirDate();
    if (d != null) {
      setState(() {
        widget.dates.add(avecHeure(d, creneauxPourType(widget.type).first));
        widget.onChanged();
      });
    }
  }

  Future<void> _modifierDate(int index) async {
    final actuel = widget.dates[index];
    final d = await _choisirDate(initial: actuel);
    if (d != null) {
      setState(() {
        final creneaux = creneauxPourType(widget.type);
        final heure = creneaux.contains(heureDe(actuel)) ? heureDe(actuel) : creneaux.first;
        widget.dates[index] = avecHeure(d, heure);
        widget.onChanged();
      });
    }
  }

  void _retirer(int index) {
    setState(() {
      widget.dates.removeAt(index);
      widget.onChanged();
    });
  }

  Future<DateTime?> _choisirDate({DateTime? initial}) {
    return showDatePicker(
      context: context,
      initialDate: initial ?? prochainJourAutorise(DateTime.now().add(const Duration(days: 60))),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr', 'FR'),
      selectableDayPredicate: estJourAutorise,
    );
  }
}
