import 'package:flutter/material.dart';

import '../../models/cote_pacte.dart';
import '../../models/remplacant.dart';
import '../../models/type_repas.dart';
import '../../services/pacte_repository.dart';
import '../../widgets/remplacants_form.dart';
import 'chat_screen.dart';

/// Espace permanent, accessible tant que le pacte est confirmé : ajouter
/// des remplaçants à tout moment (pas seulement au moment de se
/// désister), discuter avec ceux qui ont déjà un compte, et déléguer sa
/// présence à l'un d'eux. Propre à ce pacte, jamais visible par
/// l'autre partie.
class MesRemplacantsScreen extends StatefulWidget {
  final String pacteId;
  final String cote;
  final CotePacte cotePacte;
  final String nomAutrePartie;
  final TypeRepas type;
  final List<DateTime> dates;

  const MesRemplacantsScreen({
    super.key,
    required this.pacteId,
    required this.cote,
    required this.cotePacte,
    required this.nomAutrePartie,
    required this.type,
    required this.dates,
  });

  @override
  State<MesRemplacantsScreen> createState() => _MesRemplacantsScreenState();
}

class _MesRemplacantsScreenState extends State<MesRemplacantsScreen> {
  List<Remplacant> get remplacants => widget.cotePacte.listeRemplacants;

  /// id (ou identité mémoire pour un remplaçant pas encore enregistré)
  /// de celui en cours de désignation, pour désactiver son bouton.
  Object? enCoursPour;
  String? erreur;

  /// True si une désignation a eu lieu pendant cette visite de l'écran
  /// — signale à l'appelant qu'il doit rafraîchir le statut du pacte.
  bool _quelqueChoseAChange = false;

  @override
  Widget build(BuildContext context) {
    final valides = remplacants.where((r) => r.estRempli).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _quelqueChoseAChange);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Mes remplaçants')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Propres à ce pacte : cette liste ne sera jamais visible par l'autre partie. Tu peux "
              "en ajouter à tout moment, pas seulement si tu te désistes.",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            RemplacantsForm(
              remplacants: remplacants,
              minimum: 0,
              nomAutrePartie: widget.nomAutrePartie,
              type: widget.type,
              dates: widget.dates,
              onChanged: () => setState(() {}),
            ),
            if (erreur != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(erreur!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
            if (valides.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              const Text('Tes remplaçants', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final r in valides) _carteRemplacant(r),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteRemplacant(Remplacant r) {
    final aUnCompte = r.profilId != null;
    final enCours = enCoursPour == (r.id ?? r);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.nomComplet, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (r.selectionne)
                  const Text('Désigné(e) ✓',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              aUnCompte ? 'A rejoint l\'application' : "N'a pas encore rejoint l'application",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (aUnCompte)
                  OutlinedButton.icon(
                    onPressed: () => _ouvrirChat(r),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Discuter'),
                  ),
                if (!r.selectionne)
                  OutlinedButton.icon(
                    onPressed: enCours ? null : () => _designer(r),
                    icon: enCours
                        ? const SizedBox(
                            height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.person_search, size: 16),
                    label: const Text('Le/la désigner comme remplaçant'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _ouvrirChat(Remplacant r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(remplacantId: r.id!, nomInterlocuteur: r.nomComplet),
      ),
    );
  }

  Future<void> _designer(Remplacant r) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer'),
        content: Text('Désigner ${r.nomComplet} comme ton remplaçant pour ce pacte ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirme != true) return;

    setState(() {
      enCoursPour = r.id ?? r;
      erreur = null;
    });
    try {
      await PacteRepository.synchroniserRemplacants(widget.pacteId, widget.cote, remplacants);
      await PacteRepository.selectionnerRemplacant(r.id!);
      if (!mounted) return;
      setState(() {
        r.selectionne = true;
        enCoursPour = null;
        _quelqueChoseAChange = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        enCoursPour = null;
        erreur = "Impossible d'enregistrer ce choix pour le moment. Réessaie.";
      });
    }
  }
}
