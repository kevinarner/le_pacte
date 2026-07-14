import 'package:flutter/material.dart';

import 'screens/login/login_screen.dart';
import 'theme/app_theme.dart';

class PacteApp extends StatelessWidget {
  const PacteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Le Pacte (test)',
      theme: buildAppTheme(),
      home: const LoginScreen(),
    );
  }
}
