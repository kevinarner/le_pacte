import 'package:flutter/material.dart';

import '../../screens/login/login_screen.dart';
import '../accueil/accueil_screen.dart';
import '../profil/profil_screen.dart';
import '../remplacants/remplacants_screen.dart';

/// Coquille principale : nav basse (Pactes / Remplaçants / Profil).
/// Créer un pacte et Détail d'un pacte s'ouvrent par-dessus, sans nav basse.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int index = 0;
  bool perspectiveMoi = true;

  void refresh() => setState(() {});

  void changerPerspective() => setState(() => perspectiveMoi = !perspectiveMoi);

  void deconnexion() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ecrans = [
      AccueilScreen(
        perspectiveMoi: perspectiveMoi,
        onChangerPerspective: changerPerspective,
        onChanged: refresh,
      ),
      RemplacantsScreen(perspectiveMoi: perspectiveMoi, onChanged: refresh),
      ProfilScreen(
        perspectiveMoi: perspectiveMoi,
        onChangerPerspective: changerPerspective,
        onDeconnexion: deconnexion,
        onChanged: refresh,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: ecrans),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Pactes'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Remplaçants'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }
}
