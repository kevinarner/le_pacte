import '../utils/date_fr.dart';

/// Délai minimum avant un Swend (D-025) : pour un Swend créé par un
/// utilisateur standard, aucune date (proposée ou retenue) avant la date de
/// création (heure de Paris) + 15 jours. La base calcule et impose cette
/// date (`pactes.date_minimale`, `date_minimale_nouveau_swend()`) ; l'app ne
/// s'en sert que pour le calendrier et un message clair. Null : pas de
/// limite (Swend créé par un compte fondateur, ou antérieur à la règle).

/// « 2026-10-16 » (colonne `date` de la base) → 16 octobre 2026, ou null.
DateTime? dateMinimaleDepuis(Object? valeur) {
  if (valeur is! String || valeur.isEmpty) return null;
  final d = DateTime.tryParse(valeur);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Premier jour sélectionnable dans le calendrier : aujourd'hui, ou la date
/// minimale si elle est plus tardive.
DateTime premierJourSelectionnable(DateTime maintenant, DateTime? dateMinimale) {
  final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
  if (dateMinimale == null || dateMinimale.isBefore(aujourdhui)) return aujourdhui;
  return dateMinimale;
}

/// La date (jour) respecte-t-elle la date minimale ?
bool respecteDateMinimale(DateTime date, DateTime? dateMinimale) =>
    dateMinimale == null ||
    !DateTime(date.year, date.month, date.day).isBefore(dateMinimale);

/// Message affiché quand une date est trop proche (refus de la base, ou
/// contrôle avant l'envoi).
String messageDateTropProche(DateTime dateMinimale) =>
    'Choisissez une date au moins 15 jours à l’avance. '
    'Première date possible : ${dateMinimale.day} ${moisAnnee[dateMinimale.month - 1]}.';
