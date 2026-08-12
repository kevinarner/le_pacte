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

  /// Créneaux réellement proposés par le restaurant du pacte, pour son
  /// type de repas.
  List<TimeOfDay> get _creneaux =>
      widget.pacte.restaurantsProposes.first.creneaux(widget.pacte.type);

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
        const Text('Choisis une date et un horaire qui te conviennent :',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final date in pacte.datesProposees)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(formaterDateEtHeure(date)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _choisirDate(date),
                ),
                if (peutContreProposer)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _proposerAutreHoraire(date),
                        icon: const Icon(Icons.schedule, size: 16),
                        label: const Text('Cette date me convient, mais pas cet horaire'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
              ],
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
        DatesForm(
          dates: nouvellesDates,
          creneaux: _creneaux,
          onChanged: () => setState(() {}),
        ),
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

  Future<void> _proposerAutreHoraire(DateTime date) async {
    final creneaux = _creneaux;
    final heureActuelle = heureDe(date);
    final choix = await showModalBottomSheet<TimeOfDay>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choisis un autre horaire pour le ${formaterDateEnToutesLettres(date)} :',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final c in creneaux)
              RadioListTile<TimeOfDay>(
                title: Text(formaterHeure(c)),
                value: c,
                groupValue: heureActuelle,
                onChanged: (v) => Navigator.pop(context, v),
              ),
          ],
        ),
      ),
    );
    if (choix != null) {
      nouvellesDates
        ..clear()
        ..add(avecHeure(date, choix));
      _validerContreProposition();
    }
  }
}
