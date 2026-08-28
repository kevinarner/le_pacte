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
      // ignore: avoid_print
      print('[Le Pacte] Permission notifications : ${reglages.authorizationStatus}');
      if (reglages.authorizationStatus == AuthorizationStatus.denied) return;

      await _enregistrerToken();
      _messaging.onTokenRefresh.listen((_) => _enregistrerToken());

      FirebaseMessaging.onMessage.listen((message) {
        // ignore: avoid_print
        print('[Le Pacte] Notification reçue au premier plan : ${message.notification?.title}');
      });

      FirebaseMessaging.onMessageOpenedApp.listen(_gererClicNotification);
      final messageInitial = await _messaging.getInitialMessage();
      if (messageInitial != null) _gererClicNotification(messageInitial);
    } catch (e) {
      // ignore: avoid_print
      print('[Le Pacte] Initialisation FCM impossible pour le moment : $e');
    }
  }

  static void _gererClicNotification(RemoteMessage message) {
    // ignore: avoid_print
    print('[Le Pacte] Notification ouverte : ${message.data}');
  }

  static Future<void> _enregistrerToken() async {
    try {
      // Sur le web, le service worker doit être cherché relativement à la
      // base de l'app (l'app est servie depuis un sous-dossier GitHub
      // Pages, /le_pacte/, pas la racine du domaine).
      final token = kIsWeb
          ? await _messaging.getToken(
              vapidKey: firebaseVapidKey,
              serviceWorkerScriptPath: 'firebase-messaging-sw.js',
            )
          : await _messaging.getToken();
      // ignore: avoid_print
      print('[Le Pacte] Token FCM obtenu : ${token != null}');
      if (token == null || AppStore.moi.id.isEmpty) return;

      await _client.from('device_tokens').upsert(
        {
          'profile_id': AppStore.moi.id,
          'token': token,
          'plateforme': kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
        },
        onConflict: 'token',
      );
      // ignore: avoid_print
      print('[Le Pacte] Token FCM enregistré dans device_tokens.');
    } catch (e) {
      // ignore: avoid_print
      print("[Le Pacte] Impossible d'enregistrer le token FCM : $e");
    }
  }

  /// À appeler à la déconnexion volontaire pour ne plus recevoir sur cet
  /// appareil de notifications destinées à ce compte.
  static Future<void> supprimerTokenAppareil() async {
    try {
      // Sur le web, le service worker doit être cherché relativement à la
      // base de l'app (l'app est servie depuis un sous-dossier GitHub
      // Pages, /le_pacte/, pas la racine du domaine).
      final token = kIsWeb
          ? await _messaging.getToken(
              vapidKey: firebaseVapidKey,
              serviceWorkerScriptPath: 'firebase-messaging-sw.js',
            )
          : await _messaging.getToken();
      if (token == null) return;
      await _client.from('device_tokens').delete().eq('token', token);
    } catch (_) {
      // Pas grave si ça échoue : le token expire de lui-même côté FCM.
    }
  }
}
