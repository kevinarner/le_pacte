import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/remplacant.dart';
import '../../models/type_repas.dart';
import '../../widgets/remplacants_form.dart';

/// Saisie des remplaçants du destinataire pour CE pacte, puis choix de
/// celui à qui déléguer. Propre à ce pacte, jamais visible par l'initiateur.
class ChoisirRemplacantScreen extends StatefulWidget {
  final CotePacte cote;
  final String nomAutrePartie;
  final TypeRepas type;
  final List<DateTime> dates;

  const ChoisirRemplacantScreen({
    super.key,
    required this.cote,
    required this.nomAutrePartie,
    required this.type,
    required this.dates,
  });

  @override
  State<ChoisirRemplacantScreen> createState() => _ChoisirRemplacantScreenState();
}

class _ChoisirRemplacantScreenState extends State<ChoisirRemplacantScreen> {
  List<Remplacant> get remplacants => widget.cote.listeRemplacants;

  @override
  Widget build(BuildContext context) {
    final valides = remplacants.where((r) => r.estRempli).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes remplaçants')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Renseigne au moins 2 remplaçants pour ce pacte, puis choisis celui que tu délègues. '
            "Cette liste reste connue de toi seul.",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          RemplacantsForm(
            remplacants: remplacants,
            nomAutrePartie: widget.nomAutrePartie,
            type: widget.type,
            dates: widget.dates,
            onChanged: () => setState(() {}),
          ),
          if (valides.length >= 2) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Choisir qui te remplace :', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final r in valides)
              Card(
                child: ListTile(
                  title: Text(r.nomComplet),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, r),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
