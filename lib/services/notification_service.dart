import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import 'app_store.dart';

/// Gère l'inscription aux notifications push (FCM) : demande de
/// permission, récupération et sauvegarde du token de cet appareil.
/// Le routage précis au clic sur une notification (vers le pacte ou le
/// chat concerné) sera branché avec le format des messages envoyés par
/// la fonction serveur (voir device_tokens / Edge Function).
class NotificationService {
  static SupabaseClient get _client => Supabase.instance.client;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static bool _initialise = false;

  /// À appeler une fois l'utilisateur connecté (AppStore.moi.id renseigné) :
  /// à l'arrivée sur RootShell, que ce soit juste après connexion ou après
  /// une reconnexion forcée.
  static Future<void> initialiser() async {
    if (_initialise) return;
    _initialise = true;

    try {
      final reglages = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      if (reglages.authorizationStatus == AuthorizationStatus.denied) return;

      await _enregistrerToken();
      _messaging.onTokenRefresh.listen((_) => _enregistrerToken());

      FirebaseMessaging.onMessage.listen((message) {
        developer.log('Notification reçue au premier plan : ${message.notification?.title}',
            name: 'NotificationService');
      });

      FirebaseMessaging.onMessageOpenedApp.listen(_gererClicNotification);
      final messageInitial = await _messaging.getInitialMessage();
      if (messageInitial != null) _gererClicNotification(messageInitial);
    } catch (e) {
      developer.log("Initialisation FCM impossible pour le moment : $e",
          name: 'NotificationService');
    }
  }

  static void _gererClicNotification(RemoteMessage message) {
    developer.log('Notification ouverte : ${message.data}', name: 'NotificationService');
  }

  static Future<void> _enregistrerToken() async {
    try {
      final token = kIsWeb
          ? await _messaging.getToken(vapidKey: firebaseVapidKey)
          : await _messaging.getToken();
      if (token == null || AppStore.moi.id.isEmpty) return;

      await _client.from('device_tokens').upsert(
        {
          'utilisateur_id': AppStore.moi.id,
          'token': token,
          'plateforme': kIsWeb ? 'web' : defaultTargetPlatform.name,
        },
        onConflict: 'token',
      );
    } catch (e) {
      developer.log("Impossible d'enregistrer le token FCM : $e", name: 'NotificationService');
    }
  }

  /// À appeler à la déconnexion volontaire pour ne plus recevoir sur cet
  /// appareil de notifications destinées à ce compte.
  static Future<void> supprimerTokenAppareil() async {
    try {
      final token = kIsWeb
          ? await _messaging.getToken(vapidKey: firebaseVapidKey)
          : await _messaging.getToken();
      if (token == null) return;
      await _client.from('device_tokens').delete().eq('token', token);
    } catch (_) {
      // Pas grave si ça échoue : le token expire de lui-même côté FCM.
    }
  }
}
