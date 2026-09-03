import 'package:flutter/material.dart';

import '../../models/fil_de_discussion.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_fr.dart';
import '../detail_pacte/chat_screen.dart';

/// Regroupe tous les fils de discussion au même endroit — qu'on soit
/// titulaire (avec ses remplaçants) ou remplaçant (avec son titulaire),
/// plutôt que dispersés pacte par pacte.
class MessagerieScreen extends StatefulWidget {
  const MessagerieScreen({super.key});

  @override
  State<MessagerieScreen> createState() => _MessagerieScreenState();
}

class _MessagerieScreenState extends State<MessagerieScreen> {
  List<FilDeDiscussion>? fils;
  String? erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      erreur = null;
      fils = null;
    });
    try {
      final resultat = await PacteRepository.mesFilsDeDiscussion();
      if (!mounted) return;
      setState(() => fils = resultat);
    } catch (e) {
      if (!mounted) return;
      setState(() => erreur = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = fils;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Image.asset('assets/images/logo_mains.png'),
          tooltip: 'Menu principal',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Messagerie'),
      ),
      body: erreur != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.erreur, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      "Impossible de charger tes conversations.\n$erreur",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.erreur, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _charger, child: const Text('Réessayer')),
                  ],
                ),
              ),
            )
          : liste == null
              ? const Center(child: CircularProgressIndicator())
              : liste.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "Aucune conversation pour l'instant.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _charger,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: liste.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _ligne(liste[i]),
                      ),
                    ),
    );
  }

  Widget _ligne(FilDeDiscussion fil) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.pecheClair,
        foregroundColor: AppColors.peche,
        child: Text(fil.nomInterlocuteur.isNotEmpty ? fil.nomInterlocuteur[0].toUpperCase() : '?'),
      ),
      title: Text(fil.nomInterlocuteur, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fil.dateConcernee != null && fil.restaurantNom != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${_libelleDateCourt(fil.dateConcernee!)} · ${fil.restaurantNom}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.accentFonce,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            fil.dernierMessage ?? "Aucun message pour l'instant",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fil.dernierMessage == null ? Colors.black38 : Colors.black54,
              fontStyle: fil.dernierMessage == null ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
      trailing: fil.dateDernierMessage != null
          ? Text(_libelleDate(fil.dateDernierMessage!),
              style: const TextStyle(fontSize: 11, color: Colors.black45))
          : null,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              remplacantId: fil.remplacantId,
              nomInterlocuteur: fil.nomInterlocuteur,
              telephoneInterlocuteur: fil.telephoneInterlocuteur,
            ),
          ),
        );
        await _charger();
      },
    );
  }

  String _libelleDateCourt(DateTime date) =>
      '${date.day} ${moisAnnee[date.month - 1].substring(0, 3)}.';

  String _libelleDate(DateTime date) {
    final maintenant = DateTime.now();
    final auj = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final jourMessage = DateTime(date.year, date.month, date.day);
    final diff = auj.difference(jourMessage).inDays;
    if (diff == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'Hier';
    if (diff < 7) {
      const jours = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
      return jours[date.weekday - 1];
    }
    return '${date.day}/${date.month}';
  }
}
