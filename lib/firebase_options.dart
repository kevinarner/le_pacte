// Généré manuellement à partir de la configuration récupérée dans la
// console Firebase (équivalent de ce que produirait `flutterfire configure`,
// indisponible ici car il nécessite une connexion navigateur interactive).
//
// Ces valeurs ne sont pas des secrets : elles sont embarquées dans le
// bundle client (web/APK/IPA) et servent uniquement à identifier le
// projet Firebase auprès de Google, pas à authentifier des requêtes
// serveur à serveur.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions ne supporte pas cette plateforme : $defaultTargetPlatform',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDdF4ipuM92GN1GWio_FebRVgV5wR-i0wo',
    appId: '1:409929231979:web:379d26caf7a29d25e68b2e',
    messagingSenderId: '409929231979',
    projectId: 'le-pacte-e6c17',
    authDomain: 'le-pacte-e6c17.firebaseapp.com',
    storageBucket: 'le-pacte-e6c17.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBmDnd-iCnGY9fbYo-0cAwh_abQj1Lf8lQ',
    appId: '1:409929231979:android:47d941ee96898184e68b2e',
    messagingSenderId: '409929231979',
    projectId: 'le-pacte-e6c17',
    storageBucket: 'le-pacte-e6c17.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCOWEYx0lKGt-4F8ComgRN8DqQvb5z28Rg',
    appId: '1:409929231979:ios:459759ba7cf41cdfe68b2e',
    messagingSenderId: '409929231979',
    projectId: 'le-pacte-e6c17',
    storageBucket: 'le-pacte-e6c17.firebasestorage.app',
    iosBundleId: 'com.kevinarner.lePacte',
  );
}
