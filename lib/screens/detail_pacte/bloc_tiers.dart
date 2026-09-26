import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/demande_statut.dart';
import '../../models/pacte.dart';
import '../../models/perspective_pacte.dart';
import '../../models/remplacant.dart';
import '../../models/statut_pacte.dart';
import '../../models/type_repas.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../../utils/noms.dart';
import 'chat_screen.dart';

/// Corps de la fiche d'un Swend pour une personne tierce "en cas
/// d'imprévu" — jamais celui d'un titulaire. Volontairement séparé des
/// blocs titulaire (date, réponse, gestion, "Un imprévu ?") : aucune de
/// ces actions n'existe ici, elle ne peut donc pas être atteinte par
/// erreur. Seules actions possibles : écrire au titulaire, répondre à une
/// demande (dans la conversation), se désister si elle a accepté.
class BlocTiers extends StatefulWidget {
  final Pacte pacte;
  final PerspectivePacte perspective;
  final Future<void> Function() onRecharger;

  const BlocTiers({
    super.key,
    required this.pacte,
    required this.perspective,
    required this.onRecharger,
  });

  @override
  State<BlocTiers> createState() => _BlocTiersState();
}

class _BlocTiersState extends State<BlocTiers> {
  bool _enCours = false;

  Remplacant get _fiche => widget.perspective.maFiche!;
  String get _titulaire =>
      prenomDe(widget.perspective.coteTitulaire!.nomTitulaire);
  String get _autre =>
      prenomDe(widget.perspective.coteAutreParticipant!.nomTitulaire);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [_carteInfos(), const SizedBox(height: 16), _carteEtat()],
    );
  }

  Widget _carteInfos() {
    final pacte = widget.pacte;
    final restaurant = pacte.restaurantRetenu;
    const secondaire = TextStyle(fontSize: 14, color: AppColors.texteAttenue);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pacte.type == TypeRepas.dejeuner ? 'Déjeuner' : 'Dîner',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.texteAttenue,
              ),
            ),
            const SizedBox(height: 6),
            if (pacte.dateRetenue != null)
              Text(
                formaterJourEtHeureCourt(pacte.dateRetenue!),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              )
            else
              const Text('Date encore en discussion', style: secondaire),
            if (restaurant != null) ...[
              const SizedBox(height: 4),
              Text(restaurant.nom, style: const TextStyle(fontSize: 15)),
            ],
            const SizedBox(height: 4),
            Text('Avec $_autre', style: secondaire),
            if (restaurant != null && restaurant.lien.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse(restaurant.lien),
                  webOnlyWindowName: '_blank',
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Voir le restaurant',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.north_east, size: 13, color: AppColors.accent),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteEtat() {
    final statut = widget.pacte.statut;
    final List<Widget> contenu;

    if (statut == StatutPacte.annule ||
        statut == StatutPacte.annuleDoubleAbsence) {
      contenu = [_texte('Ce Swend a été annulé.')];
    } else if (statut == StatutPacte.maintenu) {
      contenu = [_texte('Ce Swend a eu lieu.')];
    } else if (statut != StatutPacte.confirme) {
      contenu = [
        _texte(
          "$_titulaire pourra faire appel à toi en cas d'imprévu, une fois la date fixée.",
        ),
        const SizedBox(height: 14),
        _boutonEcrire(principal: false),
      ];
    } else if (_fiche.selectionne) {
      contenu = [
        _titre('Tu prends la place ${deNom(_titulaire)}'),
        const SizedBox(height: 6),
        _texte("$_autre ne saura pas que c'est toi."),
        const SizedBox(height: 16),
        _boutonEcrire(principal: true),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.erreur),
            onPressed: _enCours ? null : _seDesister,
            child: const Text('Je ne peux finalement plus venir'),
          ),
        ),
      ];
    } else {
      switch (_fiche.demandeStatut) {
        case DemandeStatut.envoyee:
          contenu = [
            _titre('$_titulaire a un imprévu'),
            const SizedBox(height: 6),
            _texte('$_titulaire te demande de prendre sa place pour ce Swend.'),
            const SizedBox(height: 10),
            _mystere(
              '$_autre ne saura pas que tu prends la place ${deNom(_titulaire)}.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _ouvrirConversation,
              child: const Text('Voir la demande et répondre'),
            ),
          ];
        case null:
          contenu = [
            _texte("$_titulaire peut faire appel à toi en cas d'imprévu."),
            const SizedBox(height: 4),
            _texte("Tu n'as rien à faire pour le moment."),
            const SizedBox(height: 14),
            _boutonEcrire(principal: false),
          ];
        case DemandeStatut.refusee:
          contenu = [
            _texte(
              'Tu as indiqué ne pas être disponible pour prendre la place ${deNom(_titulaire)}.',
            ),
            const SizedBox(height: 14),
            _boutonEcrire(principal: false),
          ];
        case DemandeStatut.cloturee:
          contenu = [
            _texte("C'est bon, quelqu'un a pu prendre la place ${deNom(_titulaire)}."),
            const SizedBox(height: 14),
            _boutonEcrire(principal: false),
          ];
        case DemandeStatut.desistee:
        case DemandeStatut.acceptee:
          contenu = [
            _texte('Tu ne prends plus la place ${deNom(_titulaire)}.'),
            const SizedBox(height: 14),
            _boutonEcrire(principal: false),
          ];
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: contenu,
        ),
      ),
    );
  }

  Widget _titre(String texte) => Text(
    texte,
    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
  );

  Widget _texte(String texte) => Text(
    texte,
    style: const TextStyle(fontSize: 14, color: AppColors.texte),
  );

  Widget _mystere(String texte) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.visibility_off_outlined, size: 16, color: AppColors.accent),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          texte,
          style: const TextStyle(fontSize: 13, color: AppColors.accentFonce),
        ),
      ),
    ],
  );

  Widget _boutonEcrire({required bool principal}) {
    final label = Text('Écrire à $_titulaire');
    const icone = Icon(Icons.chat_bubble_outline, size: 16);
    return principal
        ? FilledButton.icon(
            onPressed: _ouvrirConversation,
            icon: icone,
            label: label,
          )
        : OutlinedButton.icon(
            onPressed: _ouvrirConversation,
            icon: icone,
            label: label,
          );
  }

  Future<void> _ouvrirConversation() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          remplacantId: _fiche.id!,
          nomInterlocuteur: widget.perspective.coteTitulaire!.nomTitulaire,
          depuisFiche: true,
        ),
      ),
    );
    await widget.onRecharger();
  }

  Future<void> _seDesister() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tu ne peux finalement plus venir ?'),
        content: Text(
          "Tu ne prendras plus la place ${deNom(_titulaire)}, qui devra chercher quelqu'un d'autre. "
          'Pense à lui écrire un mot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Je ne peux plus venir'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    setState(() => _enCours = true);
    try {
      await PacteRepository.seDesister(_fiche.id!);
    } catch (e) {
      if (mounted) {
        final code = PacteRepository.codeErreurMetier(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              code == 'swend_inactif'
                  ? "Ce Swend n'est plus actif."
                  : code == 'demande_non_active'
                  ? 'Tu ne prends déjà plus cette place.'
                  : 'Impossible pour le moment. Réessaie.',
            ),
          ),
        );
      }
    }
    await widget.onRecharger();
    if (mounted) setState(() => _enCours = false);
  }
}
