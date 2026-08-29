import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login/login_screen.dart';
import 'theme/app_theme.dart';

/// Permet d'afficher une bannière (SnackBar) depuis n'importe où dans
/// l'app, y compris depuis NotificationService qui n'a pas de
/// BuildContext à lui — utilisé pour les notifications reçues pendant
/// que l'app est ouverte (elles n'affichent rien automatiquement dans
/// ce cas, contrairement à une notification système).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Permet de naviguer depuis n'importe où, y compris depuis
/// NotificationService au clic sur une notification (avant même que
/// l'écran concerné ait le moindre BuildContext disponible).
final navigatorKey = GlobalKey<NavigatorState>();

class PacteApp extends StatelessWidget {
  const PacteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Le Pacte (test)',
      theme: buildAppTheme(),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LoginScreen(),
    );
  }
}
