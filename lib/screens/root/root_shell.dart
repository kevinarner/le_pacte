import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/login/login_screen.dart';
import '../accueil/accueil_screen.dart';
import '../profil/profil_screen.dart';

/// Coquille principale : nav basse (Pactes / Profil).
/// Créer un pacte et Détail d'un pacte s'ouvrent par-dessus, sans nav basse.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int index = 0;

  void refresh() => setState(() {});

  Future<void> deconnexion() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ecrans = [
      AccueilScreen(onChanged: refresh),
      ProfilScreen(onDeconnexion: deconnexion, onChanged: refresh),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: ecrans),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Pactes'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }
}
