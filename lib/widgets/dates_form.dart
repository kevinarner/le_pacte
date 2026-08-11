import 'package:flutter/material.dart';

import '../utils/date_fr.dart';

/// Formulaire de saisie d'une liste de dates proposées pour un pacte.
/// Mute directement [dates] (ajout/suppression/modification).
class DatesForm extends StatefulWidget {
  final List<DateTime> dates;
  final VoidCallback onChanged;
  final int minimum;

  const DatesForm({
    super.key,
    required this.dates,
    required this.onChanged,
    this.minimum = 1,
  });

  @override
  State<DatesForm> createState() => _DatesFormState();
}

class _DatesFormState extends State<DatesForm> {
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.calendar_today),
        title: Text(formaterDateEnToutesLettres(widget.dates[index])),
        onTap: () => _modifierDate(index),
        trailing: widget.dates.length > widget.minimum
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _retirer(index),
              )
            : null,
      ),
    );
  }

  Future<void> _ajouterDate() async {
    final d = await _choisirDate();
    if (d != null) {
      setState(() {
        widget.dates.add(d);
        widget.onChanged();
      });
    }
  }

  Future<void> _modifierDate(int index) async {
    final d = await _choisirDate(initial: widget.dates[index]);
    if (d != null) {
      setState(() {
        widget.dates[index] = d;
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
