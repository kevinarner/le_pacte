import '../utils/date_fr.dart';
import '../utils/heure_paris.dart';

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

/// Premier jour sélectionnable dans le calendrier : [aujourdhui] (jour
/// civil de Paris, [aujourdhuiParis]), ou la date minimale si elle est plus
/// tardive.
DateTime premierJourSelectionnable(DateTime aujourdhui, DateTime? dateMinimale) {
  final jour = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  if (dateMinimale == null || dateMinimale.isBefore(jour)) return jour;
  return dateMinimale;
}

/// Le jour de Paris de cet instant de rendez-vous respecte-t-il la date
/// minimale ? (même calcul que la base : jour de Paris ≥ date minimale)
bool respecteDateMinimale(DateTime instant, DateTime? dateMinimale) =>
    dateMinimale == null || !jourParis(instant).isBefore(dateMinimale);

/// Refus de la base pour une date sans fuseau (`date_sans_fuseau`) ou une
/// date retenue absente des dates proposées (`date_non_proposee`, D-025b) :
/// n'arrive qu'avec une version périmée de l'app (R2).
const messageDateRefusee =
    'Cette date n’a pas pu être enregistrée. Rechargez l’app puis réessayez.';

/// Message affiché quand une date est trop proche (refus de la base, ou
/// contrôle avant l'envoi).
String messageDateTropProche(DateTime dateMinimale) =>
    'Choisissez une date au moins 15 jours à l’avance. '
    'Première date possible : ${dateMinimale.day} ${moisAnnee[dateMinimale.month - 1]}.';
