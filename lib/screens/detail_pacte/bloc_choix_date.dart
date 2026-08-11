import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../utils/date_fr.dart';
import '../../widgets/dates_form.dart';

/// Nombre maximum d'allers-retours de négociation avant annulation
/// automatique du pacte (aucune date trouvée).
const int maxEchangesDate = 2;

/// Bloc affiché au participant dont c'est le tour de choisir une date
/// parmi celles proposées par l'autre — ou d'en proposer d'autres,
/// dans la limite de [maxEchangesDate] allers-retours.
class BlocChoixDate extends StatefulWidget {
  final Pacte pacte;
  final bool jeSuisInitiateur;
  final VoidCallback onChanged;

  const BlocChoixDate({
    super.key,
    required this.pacte,
    required this.jeSuisInitiateur,
    required this.onChanged,
  });

  @override
  State<BlocChoixDate> createState() => _BlocChoixDateState();
}

class _BlocChoixDateState extends State<BlocChoixDate> {
  bool contrePropositionEnCours = false;
  final List<DateTime> nouvellesDates = [];

  @override
  Widget build(BuildContext context) {
    if (contrePropositionEnCours) {
      return _buildContreProposition();
    }

    final pacte = widget.pacte;
    final peutContreProposer = pacte.nombreEchangesDate < maxEchangesDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Choisis une date qui te convient :',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final date in pacte.datesProposees)
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(formaterDateEnToutesLettres(date)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _choisirDate(date),
            ),
          ),
        const SizedBox(height: 8),
        if (peutContreProposer) ...[
          const Text(
            "Aucune de ces dates ne te convient ?",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() => contrePropositionEnCours = true),
            child: const Text("Proposer d'autres dates"),
          ),
        ] else
          const Text(
            "Dernière proposition : si aucune de ces dates ne convient, "
            "le pacte sera annulé.",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        const SizedBox(height: 8),
        TextButton(onPressed: _annuler, child: const Text('Annuler le pacte')),
      ],
    );
  }

  Widget _buildContreProposition() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Propose une ou plusieurs nouvelles dates :',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DatesForm(dates: nouvellesDates, onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: nouvellesDates.isNotEmpty ? _validerContreProposition : null,
          child: const Text('Envoyer ces dates'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            contrePropositionEnCours = false;
            nouvellesDates.clear();
          }),
          child: const Text('Retour'),
        ),
      ],
    );
  }

  void _choisirDate(DateTime date) {
    widget.pacte.dateRetenue = date;
    widget.pacte.statut = StatutPacte.enAttenteReponse;
    widget.onChanged();
  }

  void _validerContreProposition() {
    widget.pacte.datesProposees = List.of(nouvellesDates);
    widget.pacte.nombreEchangesDate += 1;
    widget.pacte.statut = widget.jeSuisInitiateur
        ? StatutPacte.enAttenteChoixDateDestinataire
        : StatutPacte.enAttenteChoixDateInitiateur;
    widget.onChanged();
  }

  void _annuler() {
    widget.pacte.statut = StatutPacte.annule;
    widget.onChanged();
  }
}
