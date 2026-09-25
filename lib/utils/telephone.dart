/// Numéros de téléphone : mêmes règles, à l'identique, que la fonction
/// `normaliser_telephone()` en base (qui reste la seule autorité : ce
/// fichier ne sert qu'à valider tout de suite dans les formulaires, à
/// afficher, et à construire les liens d'envoi).
///
/// Forme canonique E.164 d'un numéro de MOBILE, ou null :
///  * séparateurs ignorés (espaces, espaces insécables, . ( ) / tirets) ;
///  * "+" ou "00" = indicatif international ;
///  * sans indicatif : numéro national français à 10 chiffres ;
///  * "(0)" après +33 ou un indicatif d'outre-mer est retiré ;
///  * mobiles d'outre-mer ramenés à leur indicatif (0692 → +262…) ;
///  * France : mobiles 06/07 uniquement ; autres pays : E.164 valide.
library;

final _separateurs = RegExp(
  '[ \t\n\r\f\v    .()/‐‑‒–-]',
);

bool _correspond(String motif, String texte) => RegExp(motif).hasMatch(texte);

String? normaliserTelephone(String? saisie) {
  if (saisie == null) return null;
  final s = saisie.replaceAll(_separateurs, '');

  String d;
  if (s.startsWith('+')) {
    d = s.substring(1);
  } else if (s.startsWith('00')) {
    d = s.substring(2);
  } else if (_correspond(r'^0[0-9]{9}$', s)) {
    d = '33${s.substring(1)}';
  } else {
    return null;
  }

  if (!_correspond(r'^[0-9]+$', d)) return null;

  if (_correspond(r'^(33|262|590|594|596)0[0-9]{9}$', d)) {
    d = d.substring(0, d.length - 10) + d.substring(d.length - 9);
  }

  if (_correspond(r'^33(639|69[23])[0-9]{6}$', d)) {
    d = '262${d.substring(2)}';
  } else if (_correspond(r'^3369[01][0-9]{6}$', d)) {
    d = '590${d.substring(2)}';
  } else if (_correspond(r'^33694[0-9]{6}$', d)) {
    d = '594${d.substring(2)}';
  } else if (_correspond(r'^3369[67][0-9]{6}$', d)) {
    d = '596${d.substring(2)}';
  }

  final bool valide;
  if (d.startsWith('33')) {
    valide = _correspond(r'^33[67][0-9]{8}$', d);
  } else if (d.startsWith('262')) {
    valide = _correspond(r'^262(639|69[23])[0-9]{6}$', d);
  } else if (d.startsWith('590')) {
    valide = _correspond(r'^59069[01][0-9]{6}$', d);
  } else if (d.startsWith('594')) {
    valide = _correspond(r'^594694[0-9]{6}$', d);
  } else if (d.startsWith('596')) {
    valide = _correspond(r'^59669[67][0-9]{6}$', d);
  } else {
    valide = _correspond(r'^[1-9][0-9]{7,14}$', d);
  }
  return valide ? '+$d' : null;
}

bool telephoneValide(String? saisie) => normaliserTelephone(saisie) != null;

/// Message affiché sous un champ dont le numéro n'est pas un mobile valide.
const messageTelephoneInvalide =
    'Numéro de mobile invalide. Pour un numéro étranger, commence par '
    "l'indicatif (+44…).";

/// "06 70 41 92 77", "0692 12 34 56", ou la forme E.164 pour l'étranger ;
/// la saisie telle quelle si le numéro est invalide.
String formaterTelephone(String saisie) {
  final e164 = normaliserTelephone(saisie);
  if (e164 == null) return saisie.trim();
  String paires(String chiffres) => [
    for (var i = 0; i < chiffres.length; i += 2)
      chiffres.substring(i, i + 2 > chiffres.length ? chiffres.length : i + 2),
  ].join(' ');
  if (e164.startsWith('+33')) {
    return paires('0${e164.substring(3)}');
  }
  for (final indicatif in ['+262', '+590', '+594', '+596']) {
    if (e164.startsWith(indicatif)) {
      final national = '0${e164.substring(4)}';
      return '${national.substring(0, 4)} ${paires(national.substring(4))}';
    }
  }
  return e164;
}
