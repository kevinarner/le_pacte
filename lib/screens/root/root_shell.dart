import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/utilisateur.dart';
import '../../screens/login/login_screen.dart';
import '../../services/app_store.dart';
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
  bool _deconnexionVolontaire = false;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    // La session Supabase est partagée entre tous les onglets d'un même
    // navigateur (stockage local) : se connecter à un autre compte dans
    // un autre onglet remplace silencieusement celle utilisée ici. Sans
    // cette écoute, cet onglet continuerait d'agir sous une identité
    // affichée (AppStore.moi) qui ne correspond plus à la session réelle.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (_deconnexionVolontaire) return;
      final idActuel = data.session?.user.id;
      if (idActuel != AppStore.moi.id) {
        _forcerReconnexion(idActuel == null
            ? 'Tu as été déconnecté(e). Reconnecte-toi.'
            : 'Ta session a changé (connecté depuis un autre onglet). Reconnecte-toi.');
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  void refresh() => setState(() {});

  void _forcerReconnexion(String message) {
    if (!mounted) return;
    AppStore.moi = Utilisateur(id: '', nom: '');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> deconnexion() async {
    _deconnexionVolontaire = true;
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    AppStore.moi = Utilisateur(id: '', nom: '');
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
