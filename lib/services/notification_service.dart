import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import '../constants.dart';
import '../models/chat_apres_swend.dart';
import '../models/destination_rappel.dart';
import '../screens/detail_pacte/chat_apres_swend_screen.dart';
import '../screens/detail_pacte/chat_screen.dart';
import '../screens/detail_pacte/detail_pacte_screen.dart';
import '../screens/detail_pacte/imprevu_screen.dart';
import 'app_store.dart';
import 'pacte_repository.dart';

/// Gère l'inscription aux notifications push (FCM) : demande de
/// permission, récupération et sauvegarde du token de cet appareil, et
/// le routage vers le bon écran au clic sur une notification.
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
      print('[Swend] Permission notifications : ${reglages.authorizationStatus}');
      if (reglages.authorizationStatus == AuthorizationStatus.denied) return;

      await _enregistrerToken();
      _messaging.onTokenRefresh.listen((_) => _enregistrerToken());

      FirebaseMessaging.onMessage.listen((message) {
        // ignore: avoid_print
        print('[Swend] Notification reçue au premier plan : ${message.notification?.title}');
        final titre = message.notification?.title;
        final corps = message.notification?.body;
        if (titre == null && corps == null) return;
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text([titre, corps].whereType<String>().join(' — ')),
            duration: const Duration(seconds: 4),
          ),
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen(_gererClicNotification);
      final messageInitial = await _messaging.getInitialMessage();
      if (messageInitial != null) _gererClicNotification(messageInitial);
    } catch (e) {
      // ignore: avoid_print
      print('[Swend] Initialisation FCM impossible pour le moment : $e');
    }
  }

  static Future<void> _gererClicNotification(RemoteMessage message) async {
    // ignore: avoid_print
    print('[Swend] Notification ouverte : ${message.data['type']}');
    final data = message.data;
    switch (data['type']) {
      case 'pacte':
        final pacteId = data['pacte_id'] as String?;
        if (pacteId == null) return;
        final pacte = await PacteRepository.pacteParId(pacteId);
        if (pacte == null) return;
        navigatorKey.currentState
            ?.push(MaterialPageRoute(builder: (_) => DetailPacteScreen(pacte: pacte)));
      case 'rappel':
        final pacteId = data['pacte_id'] as String?;
        if (pacteId == null) return;
        await _ouvrirRappel(pacteId);
      case 'chat_apres_swend':
        // Chat après le Swend (D-023b) : l'écran lui-même affiche « Cette
        // conversation n'est plus accessible. » si l'accès a disparu.
        final chatId = data['chat_id'] as String?;
        if (chatId == null) return;
        _ouvrirChatApresSwend(chatId);
      case 'chat':
        final remplacantId = data['remplacant_id'] as String?;
        if (remplacantId == null) return;
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => ChatScreen(
            remplacantId: remplacantId,
            nomInterlocuteur: data['nom_interlocuteur'] as String? ?? '',
            telephoneInterlocuteur: data['telephone_interlocuteur'] as String?,
          ),
        ));
    }
  }

  /// Rappel J-7 / J-3 / J-1 / Jour J (D-021) : aucune destination figée
  /// dans la push, elle est recalculée maintenant par la base (le rôle a pu
  /// changer). Plus d'accès : rien ne s'ouvre, on reste sur l'accueil.
  static Future<void> _ouvrirRappel(String pacteId) async {
    final destination = destinationRappelDepuis(
        await PacteRepository.destinationRappel(pacteId));
    if (destination == null) return;
    final pacte = await PacteRepository.pacteParId(pacteId);
    if (pacte == null) return;
    final navigateur = navigatorKey.currentState;
    navigateur?.push(MaterialPageRoute(builder: (_) => DetailPacteScreen(pacte: pacte)));
    if (destination == DestinationRappel.imprevu) {
      navigateur?.push(MaterialPageRoute(
        builder: (_) => ImprevuScreen(
          pacte: pacte,
          jeSuisInitiateur: pacte.initiateur.idTitulaire == AppStore.moi.id,
          onChanged: () {},
        ),
      ));
    }
  }

  static void _ouvrirChatApresSwend(String chatId) {
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => ChatApresSwendScreen(chatId: chatId),
    ));
  }

  static String? _rappelDuLien;
  static String? _chatDuLien;

  /// Web : le clic sur un rappel ouvre l'app avec `?rappel=<pacte_id>` (le
  /// service worker Firebase ne transmet pas le clic à l'app). À appeler
  /// dans main(), avant runApp : mémorise le Swend et retire le paramètre de
  /// l'adresse avant que Flutter ne manipule l'historique du navigateur (un
  /// rechargement ne rouvre pas le rappel). callMethodVarArgs : callMethod
  /// traite un premier argument null comme « aucun argument ».
  /// Même principe pour le chat après le Swend (D-023b) : `?chat_apres=<id>`.
  static void lireLienRappel() {
    if (!kIsWeb) return;
    _rappelDuLien = pacteDuLienRappel(Uri.base);
    _chatDuLien = chatDuLien(Uri.base);
    if (_rappelDuLien == null && _chatDuLien == null) return;
    try {
      final propre = adresseSansChat(Uri.parse(adresseSansRappel(Uri.base)));
      (globalContext['history'] as JSObject).callMethodVarArgs(
          'replaceState'.toJS, [null, ''.toJS, propre.toJS]);
    } catch (_) {
      // Adresse non nettoyée : un rechargement rouvrirait le lien, sans gravité.
    }
  }

  /// À l'arrivée sur RootShell, une fois connecté : ouvre le rappel mémorisé
  /// par [lireLienRappel] (une seule fois), même destination que sur mobile.
  static void ouvrirRappelDuLien() {
    final pacteId = _rappelDuLien;
    final chatId = _chatDuLien;
    _rappelDuLien = null;
    _chatDuLien = null;
    if (pacteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ouvrirRappel(pacteId));
    }
    if (chatId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ouvrirChatApresSwend(chatId));
    }
  }

  static Future<void> _enregistrerToken({bool reessaieDeja = false}) async {
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
      print('[Swend] Token FCM obtenu : ${token != null}');
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
      print('[Swend] Token FCM enregistré dans device_tokens.');
    } catch (e) {
      // Première visite : le service worker peut ne pas encore être actif
      // au moment de s'y abonner. Une seule nouvelle tentative après un
      // court délai suffit, il est alors déjà prêt.
      if (!reessaieDeja && e.toString().contains('no active Service Worker')) {
        await Future.delayed(const Duration(seconds: 2));
        return _enregistrerToken(reessaieDeja: true);
      }
      // ignore: avoid_print
      print("[Swend] Impossible d'enregistrer le token FCM : $e");
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
