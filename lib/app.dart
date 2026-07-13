import 'package:flutter/material.dart';

import 'screens/accueil/accueil_screen.dart';

class PacteApp extends StatefulWidget {
  const PacteApp({super.key});
  @override
  State<PacteApp> createState() => _PacteAppState();
}

class _PacteAppState extends State<PacteApp> {
  // true = je suis "Moi" (identifié comme initiateur type), false = "Mon ami"
  bool perspectiveMoi = true;

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Le Pacte (test)',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C3AED),
        useMaterial3: true,
      ),
      home: AccueilScreen(
        perspectiveMoi: perspectiveMoi,
        onChangerPerspective: () => setState(() => perspectiveMoi = !perspectiveMoi),
        onChanged: refresh,
      ),
    );
  }
}
