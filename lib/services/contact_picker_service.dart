import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

/// Permet de choisir un contact directement dans le carnet d'adresses du
/// téléphone, via la Contact Picker API du navigateur (`navigator.contacts`)
/// — pour l'instant disponible uniquement sur Android + Chrome (ni iOS
/// Safari, ni desktop). Ailleurs, [disponible] renvoie false et l'app garde
/// la saisie manuelle comme seule option.
///
/// Les fonctions JS correspondantes sont définies dans web/index.html —
/// elles renvoient un JSON encodé en chaîne plutôt qu'un objet JS, pour ne
/// pas avoir à décortiquer un JSObject ici.
class ContactPickerService {
  static bool get disponible {
    if (!kIsWeb) return false;
    try {
      if (!globalContext.has('paktContactPickerDisponible')) return false;
      final resultat = globalContext.callMethod('paktContactPickerDisponible'.toJS);
      return resultat.dartify() == true;
    } catch (_) {
      return false;
    }
  }

  /// Ouvre le sélecteur de contacts natif. Renvoie {nom, telephone} ou
  /// null si l'utilisateur annule, si l'API échoue, ou si elle n'est pas
  /// disponible sur ce navigateur.
  static Future<Map<String, String>?> choisirContact() async {
    if (!kIsWeb) return null;
    try {
      if (!globalContext.has('paktChoisirContact')) return null;
      final promise = globalContext.callMethod('paktChoisirContact'.toJS) as JSPromise?;
      if (promise == null) return null;
      final resultat = await promise.toDart;
      final json = resultat.dartify() as String?;
      if (json == null) return null;
      final data = jsonDecode(json) as Map<String, dynamic>;
      return {
        'nom': (data['nom'] as String?) ?? '',
        'telephone': (data['telephone'] as String?) ?? '',
      };
    } catch (_) {
      return null;
    }
  }
}
