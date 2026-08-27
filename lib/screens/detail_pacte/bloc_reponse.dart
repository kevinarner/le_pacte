import 'package:flutter/material.dart';

import '../../models/pacte.dart';
import '../../models/statut_pacte.dart';
import '../../services/pacte_repository.dart';
import '../../widgets/remplacants_form.dart';

const _minimumRemplacants = 2;

/// Bloc affiché quand le destinataire doit répondre à un pacte :
/// accepter ou refuser. Accepter demande aussi de renseigner ses
/// propres remplaçants (comme l'initiateur le fait déjà à la
/// création) — les deux côtés pourront en ajouter d'autres plus tard,
/// à tout moment, depuis l'écran "Mes remplaçants".
class BlocReponse extends StatefulWidget {
  final Pacte pacte;
  final VoidCallback onChanged;
  const BlocReponse({super.key, required this.pacte, required this.onChanged});

  @override
  State<BlocReponse> createState() => _BlocReponseState();
}

class _BlocReponseState extends State<BlocReponse> {
  bool enCours = false;
  String? erreur;

  bool get _peutAccepter =>
      widget.pacte.destinataire.listeRemplacants.where((r) => r.estRempli).length >=
      _minimumRemplacants;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Que souhaites-tu faire ?', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Renseigne au moins 2 remplaçants avant d\'accepter :',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          "Propres à ce pacte : cette liste ne sera jamais visible par l'initiateur.",
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        RemplacantsForm(
          remplacants: widget.pacte.destinataire.listeRemplacants,
          minimum: _minimumRemplacants,
          nomAutrePartie: widget.pacte.initiateur.nomTitulaire,
          type: widget.pacte.type,
          dates: widget.pacte.dateRetenue != null ? [widget.pacte.dateRetenue!] : [],
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (erreur != null) ...[
          Text(erreur!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: _peutAccepter && !enCours ? _accepter : null,
          child: enCours
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Accepter le pacte'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: enCours ? null : _refuser,
          child: const Text('Refuser le pacte'),
        ),
      ],
    );
  }

  Future<void> _accepter() async {
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      await PacteRepository.synchroniserRemplacants(
        widget.pacte.id,
        'destinataire',
        widget.pacte.destinataire.listeRemplacants,
      );
      await PacteRepository.mettreAJourStatut(widget.pacte.id, StatutPacte.confirme);
      widget.pacte.restaurantRetenu = widget.pacte.restaurantsProposes.first;
      widget.pacte.statut = StatutPacte.confirme;
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = "Impossible d'accepter le pacte pour le moment. Réessaie.";
      });
    }
  }

  Future<void> _refuser() async {
    setState(() => enCours = true);
    try {
      await PacteRepository.mettreAJourStatut(widget.pacte.id, StatutPacte.annule);
      widget.pacte.statut = StatutPacte.annule;
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = "Impossible de refuser le pacte pour le moment. Réessaie.";
      });
    }
  }
}
