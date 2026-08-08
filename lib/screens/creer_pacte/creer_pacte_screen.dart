import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/cote_pacte.dart';
import '../../models/pacte.dart';
import '../../models/restaurant.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../theme/app_theme.dart';

const _nomRestaurant = 'Au père Lapin';
const _lienRestaurant = 'https://www.auperelapin.com/';

const _joursSemaine = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const _moisAnnee = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _formaterDateEnToutesLettres(DateTime d) =>
    '${_joursSemaine[d.weekday - 1]} ${d.day} ${_moisAnnee[d.month - 1]} ${d.year}';

bool _estJourAutorise(DateTime d) => d.weekday <= DateTime.wednesday;

DateTime _prochainJourAutorise(DateTime d) {
  var date = d;
  while (!_estJourAutorise(date)) {
    date = date.add(const Duration(days: 1));
  }
  return date;
}

class CreerPacteScreen extends StatefulWidget {
  final bool perspectiveMoi;
  const CreerPacteScreen({super.key, required this.perspectiveMoi});

  @override
  State<CreerPacteScreen> createState() => _CreerPacteScreenState();
}

class _CreerPacteScreenState extends State<CreerPacteScreen> {
  TypeRepas type = TypeRepas.diner;
  DateTime? dateChoisie;

  @override
  Widget build(BuildContext context) {
    final nomMoi = widget.perspectiveMoi ? 'Moi' : 'Mon ami';
    final nomAutre = widget.perspectiveMoi ? 'Mon ami' : 'Moi';

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau pacte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Initiateur : $nomMoi → destinataire : $nomAutre',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          const Text('Type de repas', style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<TypeRepas>(
            title: const Text('Déjeuner'),
            value: TypeRepas.dejeuner,
            groupValue: type,
            onChanged: (v) => setState(() => type = v!),
          ),
          RadioListTile<TypeRepas>(
            title: const Text('Dîner'),
            value: TypeRepas.diner,
            groupValue: type,
            onChanged: (v) => setState(() => type = v!),
          ),
          const SizedBox(height: 8),
          const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
          ListTile(
            title: Text(dateChoisie == null
                ? 'Choisir une date'
                : 'Date : ${_formaterDateEnToutesLettres(dateChoisie!)}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _prochainJourAutorise(DateTime.now().add(const Duration(days: 60))),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                locale: const Locale('fr', 'FR'),
                selectableDayPredicate: _estJourAutorise,
              );
              if (d != null) setState(() => dateChoisie = d);
            },
          ),
          const SizedBox(height: 16),
          const Text('1 restaurant proposé', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            "D'autres restaurant vont être proposés bientôt",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          const Text('Nom du restaurant', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          const Text(_nomRestaurant, style: TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          const Text('Lien du site web', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          InkWell(
            onTap: _ouvrirLienRestaurant,
            child: const Text(
              _lienRestaurant,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.terracotta,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _peutValider() ? _creerPacte : null,
            child: const Text('Envoyer le pacte'),
          ),
        ],
      ),
    );
  }

  bool _peutValider() => dateChoisie != null;

  Future<void> _ouvrirLienRestaurant() async {
    await launchUrl(Uri.parse(_lienRestaurant), webOnlyWindowName: '_blank');
  }

  void _creerPacte() {
    final date = dateChoisie;

    final restaurants = [
      Restaurant(nom: _nomRestaurant, lien: _lienRestaurant),
    ];

    final utilisateurMoi = AppStore.utilisateurCourant(widget.perspectiveMoi);
    final utilisateurAutre = AppStore.utilisateurAutre(widget.perspectiveMoi);

    final pacte = Pacte(
      id: AppStore.nouvelId(),
      type: type,
      date: date,
      dateAutomatique: false,
      restaurantsProposes: restaurants,
      initiateur: CotePacte(
        nomTitulaire: utilisateurMoi.nom,
        listeRemplacants: utilisateurMoi.remplacants,
      ),
      destinataire: CotePacte(
        nomTitulaire: utilisateurAutre.nom,
        listeRemplacants: utilisateurAutre.remplacants,
      ),
    );

    AppStore.pactes.add(pacte);
    Navigator.pop(context);
  }
}
