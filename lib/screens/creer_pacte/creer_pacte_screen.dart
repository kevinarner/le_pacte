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
const _lienTelechargementApp = 'https://kevinarner.github.io/le_pacte/';

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
  final prenomDestinataireController = TextEditingController();
  final nomDestinataireController = TextEditingController();
  final telephoneDestinataireController = TextEditingController();
  final emailDestinataireController = TextEditingController();

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
          const Text('Avec qui souhaitez-vous faire ce pacte ?',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: prenomDestinataireController,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: nomDestinataireController,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: telephoneDestinataireController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro de téléphone (optionnel)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: emailDestinataireController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Adresse email (optionnel)'),
          ),
          const SizedBox(height: 8),
          const Text(
            "Si cette personne n'a pas encore l'application, invitez-la à la télécharger :",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _inviterParSms,
                icon: const Icon(Icons.sms_outlined, size: 18),
                label: const Text('Inviter par SMS'),
              ),
              OutlinedButton.icon(
                onPressed: _inviterParEmail,
                icon: const Icon(Icons.email_outlined, size: 18),
                label: const Text('Inviter par email'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
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

  bool _peutValider() =>
      dateChoisie != null &&
      prenomDestinataireController.text.trim().isNotEmpty &&
      nomDestinataireController.text.trim().isNotEmpty;

  Future<void> _ouvrirLienRestaurant() async {
    await launchUrl(Uri.parse(_lienRestaurant), webOnlyWindowName: '_blank');
  }

  String get _nomCompletDestinataire {
    final prenom = prenomDestinataireController.text.trim();
    final nom = nomDestinataireController.text.trim();
    return [prenom, nom].where((s) => s.isNotEmpty).join(' ');
  }

  String _messageInvitation() {
    final prenom = prenomDestinataireController.text.trim();
    final salutation = prenom.isNotEmpty ? 'Salut $prenom' : 'Salut';
    return "$salutation, je t'invite à faire un pacte avec moi sur Le Pacte ! "
        'Télécharge l\'application ici : $_lienTelechargementApp';
  }

  Future<void> _inviterParSms() async {
    final numero = telephoneDestinataireController.text.trim();
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne le numéro de téléphone pour inviter par SMS.')),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'sms', path: numero, queryParameters: {'body': _messageInvitation()}));
  }

  Future<void> _inviterParEmail() async {
    final email = emailDestinataireController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne l\'adresse email pour inviter par email.')),
      );
      return;
    }
    await launchUrl(Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Invitation à un pacte', 'body': _messageInvitation()},
    ));
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
        nomTitulaire: _nomCompletDestinataire,
        listeRemplacants: utilisateurAutre.remplacants,
      ),
    );

    AppStore.pactes.add(pacte);
    Navigator.pop(context);
  }
}
