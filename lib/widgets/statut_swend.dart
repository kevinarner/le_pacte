import 'dart:async';

import 'package:flutter/material.dart';

import '../services/pacte_repository.dart';
import '../theme/app_theme.dart';
import '../utils/telephone.dart';

/// Une seule règle, partout où l'utilisateur saisit lui-même le numéro
/// d'une personne qu'il ajoute (destinataire, personne de confiance) :
///  * numéro vide, invalide, ou refusé par le formulaire ([masquer]) :
///    rien ;
///  * a déjà un compte : "[Prénom] est déjà sur Swend", pas d'invitation ;
///  * n'a pas de compte : "[Prénom] n'a pas encore Swend" et
///    "Envoyer l'invitation" (si [onInviter] est fourni).
///
/// La réponse vient de `destinataire_a_un_compte()` (oui / non, plafonnée
/// côté serveur) — jamais d'une recherche libre. Tant qu'elle n'est pas
/// arrivée, rien n'est affiché ; sans réponse (quota atteint, réseau),
/// seule l'invitation est proposée.
class StatutSwend extends StatefulWidget {
  final String prenom;
  final String telephone;
  final bool masquer;
  final VoidCallback? onInviter;

  const StatutSwend({
    super.key,
    required this.prenom,
    required this.telephone,
    this.masquer = false,
    this.onInviter,
  });

  @override
  State<StatutSwend> createState() => _StatutSwendState();
}

/// Réponses déjà obtenues, partagées par tous les formulaires : un même
/// numéro n'est demandé qu'une fois.
final Map<String, bool?> _reponses = {};
final Map<String, Future<void>> _enCours = {};

Future<void> _demander(String e164) => _enCours.putIfAbsent(e164, () async {
  try {
    _reponses[e164] = await PacteRepository.destinataireAUnCompte(e164);
  } catch (_) {
    _reponses[e164] = null;
  } finally {
    _enCours.remove(e164);
  }
});

class _StatutSwendState extends State<StatutSwend> {
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _programmer();
  }

  @override
  void didUpdateWidget(StatutSwend ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.telephone != widget.telephone ||
        ancien.masquer != widget.masquer) {
      _programmer();
    }
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  /// Demande au serveur une fois la saisie posée.
  void _programmer() {
    _minuteur?.cancel();
    final e164 = normaliserTelephone(widget.telephone);
    if (widget.masquer || e164 == null || _reponses.containsKey(e164)) return;
    _minuteur = Timer(const Duration(milliseconds: 600), () async {
      await _demander(e164);
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final e164 = normaliserTelephone(widget.telephone);
    if (widget.masquer || e164 == null || !_reponses.containsKey(e164)) {
      return const SizedBox.shrink();
    }
    final reponse = _reponses[e164];
    if (reponse == true) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LigneStatutSwend(prenom: widget.prenom, aUnCompte: true),
      );
    }

    final onInviter = widget.onInviter;
    if (reponse == null && onInviter == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reponse == false)
            LigneStatutSwend(prenom: widget.prenom, aUnCompte: false),
          if (onInviter != null) ...[
            if (reponse == false) const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onInviter,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text("Envoyer l'invitation"),
            ),
          ],
        ],
      ),
    );
  }
}

/// La phrase de statut elle-même, identique partout : "[Prénom] est déjà
/// sur Swend" / "[Prénom] n'a pas encore Swend" ("Cette personne" tant
/// que le prénom est vide). Utilisée par [StatutSwend] pendant la saisie,
/// et directement par les fiches déjà enregistrées (où la base a déjà
/// fait le rapprochement : `profil_id`).
class LigneStatutSwend extends StatelessWidget {
  final String prenom;
  final bool aUnCompte;

  const LigneStatutSwend({
    super.key,
    required this.prenom,
    required this.aUnCompte,
  });

  @override
  Widget build(BuildContext context) {
    final p = prenom.trim();
    final qui = p.isEmpty ? 'Cette personne' : p;
    if (!aUnCompte) {
      return Text(
        "$qui n'a pas encore Swend",
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    return Row(
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 18,
          color: AppColors.accent,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$qui est déjà sur Swend',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
