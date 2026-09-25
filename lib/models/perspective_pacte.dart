import 'cote_pacte.dart';
import 'demande_statut.dart';
import 'pacte.dart';
import 'remplacant.dart';

enum RolePacte { initiateur, destinataire, tiers }

/// Qui je suis sur un Swend donné, déterminé explicitement : titulaire
/// initiateur, titulaire destinataire, ou personne tierce "en cas
/// d'imprévu" (ma propre fiche remplaçant, la seule que la sécurité côté
/// base me laisse voir). Jamais de repli implicite "pas initiateur donc
/// destinataire".
class PerspectivePacte {
  final RolePacte role;

  /// Pour un tiers : sa fiche et le côté du titulaire dont il pourrait
  /// prendre (ou prend) la place.
  final Remplacant? maFiche;
  final CotePacte? coteTitulaire;
  final CotePacte? coteAutreParticipant;

  const PerspectivePacte._(
    this.role, {
    this.maFiche,
    this.coteTitulaire,
    this.coteAutreParticipant,
  });

  bool get estTitulaire => role != RolePacte.tiers;
  bool get jeSuisInitiateur => role == RolePacte.initiateur;

  /// Null si je n'ai aucun lien avec ce Swend (ne devrait pas arriver :
  /// la base ne me le renverrait pas).
  static PerspectivePacte? de(Pacte pacte, String monId) {
    if (monId.isEmpty) return null;
    if (pacte.initiateur.idTitulaire == monId) {
      return const PerspectivePacte._(RolePacte.initiateur);
    }
    if (pacte.destinataire.idTitulaire == monId) {
      return const PerspectivePacte._(RolePacte.destinataire);
    }

    final fiches = <(Remplacant, bool)>[
      for (final r in pacte.initiateur.listeRemplacants)
        if (r.profilId == monId) (r, true),
      for (final r in pacte.destinataire.listeRemplacants)
        if (r.profilId == monId) (r, false),
    ];
    if (fiches.isEmpty) return null;
    fiches.sort((a, b) => _priorite(a.$1).compareTo(_priorite(b.$1)));
    final (fiche, coteInitiateur) = fiches.first;
    return PerspectivePacte._(
      RolePacte.tiers,
      maFiche: fiche,
      coteTitulaire: coteInitiateur ? pacte.initiateur : pacte.destinataire,
      coteAutreParticipant: coteInitiateur
          ? pacte.destinataire
          : pacte.initiateur,
    );
  }

  /// Vrai si j'ai pris la place d'un titulaire de ce Swend via une autre
  /// fiche que [ficheId] — c'est alors pour ça que [ficheId] est
  /// clôturée, pas parce que quelqu'un d'autre a pris la place.
  static bool prendUnePlaceAilleurs(Pacte pacte, String monId, String ficheId) {
    return [
      ...pacte.initiateur.listeRemplacants,
      ...pacte.destinataire.listeRemplacants,
    ].any((r) => r.profilId == monId && r.id != ficheId && r.selectionne);
  }

  /// La fiche la plus "vivante" d'abord, si la même personne est prévue
  /// des deux côtés : celle où elle prend la place, puis une demande en
  /// attente, puis le reste.
  static int _priorite(Remplacant r) {
    if (r.selectionne) return 0;
    switch (r.demandeStatut) {
      case DemandeStatut.envoyee:
        return 1;
      case null:
        return 2;
      case DemandeStatut.cloturee:
      case DemandeStatut.refusee:
      case DemandeStatut.desistee:
      case DemandeStatut.acceptee:
        return 3;
    }
  }
}
