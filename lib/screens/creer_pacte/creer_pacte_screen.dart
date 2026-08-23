import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';
import '../../models/remplacant.dart';
import '../../models/restaurant.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dates_form.dart';
import '../../widgets/remplacants_form.dart';

const _minimumRemplacants = 2;

class CreerPacteScreen extends StatefulWidget {
  const CreerPacteScreen({super.key});

  @override
  State<CreerPacteScreen> createState() => _CreerPacteScreenState();
}

class _CreerPacteScreenState extends State<CreerPacteScreen> {
  TypeRepas type = TypeRepas.diner;
  final List<DateTime> datesProposees = [];
  final prenomDestinataireController = TextEditingController();
  final nomDestinataireController = TextEditingController();
  final telephoneDestinataireController = TextEditingController();
  final emailDestinataireController = TextEditingController();
  final List<Remplacant> remplacants = [];

  Restaurant? restaurant;
  bool enCours = false;
  String? erreur;
  String? erreurChargement;

  @override
  void initState() {
    super.initState();
    _chargerRestaurant();
  }

  Future<void> _chargerRestaurant() async {
    setState(() => erreurChargement = null);
    try {
      final r = await PacteRepository.restaurant();
      if (!mounted) return;
      setState(() => restaurant = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => erreurChargement = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final restau = restaurant;
    if (erreurChargement != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nouveau pacte')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppColors.terracotta, size: 32),
                const SizedBox(height: 12),
                Text(
                  "Impossible de charger le restaurant.\n$erreurChargement",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.terracotta, fontSize: 12),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _chargerRestaurant, child: const Text('Réessayer')),
              ],
            ),
          ),
        ),
      );
    }
    if (restau == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nouveau pacte')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau pacte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Avec qui souhaitez-vous faire ce pacte ?',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: prenomDestinataireController,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: nomDestinataireController,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: telephoneDestinataireController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Numéro de téléphone'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: emailDestinataireController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Adresse email (optionnel)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          const Text(
            "Si cette personne n'a pas encore l'application, invitez-la à la télécharger :",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _inviterParSms,
            icon: const Icon(Icons.sms_outlined, size: 18),
            label: const Text('Inviter par SMS'),
          ),
          const SizedBox(height: 16),
          const Text('Remplaçants potentiels (minimum 2)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            "Propres à ce pacte : cette liste ne sera jamais visible par la personne avec qui "
            "vous faites le pacte.",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          RemplacantsForm(
            remplacants: remplacants,
            minimum: _minimumRemplacants,
            nomAutrePartie: prenomDestinataireController.text.trim(),
            type: type,
            dates: datesProposees,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
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
          const Text('Dates proposées', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            "Propose une ou plusieurs dates avec un horaire : la personne avec qui tu fais "
            "ce pacte choisira celle qui lui convient.",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          DatesForm(
            dates: datesProposees,
            minimum: 1,
            creneaux: restau.creneaux(type),
            onChanged: () => setState(() {}),
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
          Text(restau.nom, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          const Text('Lien du site web', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _ouvrirLienRestaurant(restau.lien),
            child: Text(
              restau.lien,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.terracotta,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_erreursValidation().isNotEmpty) ...[
            for (final e in _erreursValidation())
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 14, color: AppColors.terracotta),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(e,
                          style: const TextStyle(fontSize: 12, color: AppColors.terracotta)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (erreur != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(erreur!, style: const TextStyle(color: AppColors.terracotta)),
            ),
          ],
          FilledButton(
            onPressed: _peutValider() && !enCours ? () => _creerPacte(restau) : null,
            child: enCours
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Envoyer le pacte'),
          ),
        ],
      ),
    );
  }

  List<String> _erreursValidation() {
    final erreurs = <String>[];
    if (prenomDestinataireController.text.trim().isEmpty ||
        nomDestinataireController.text.trim().isEmpty) {
      erreurs.add('Renseigne le prénom et le nom de la personne avec qui tu fais ce pacte.');
    }
    final nombreRemplacantsValides = remplacants.where((r) => r.estRempli).length;
    if (nombreRemplacantsValides < _minimumRemplacants) {
      final manquants = _minimumRemplacants - nombreRemplacantsValides;
      erreurs.add(
          'Ajoute encore $manquants remplaçant${manquants > 1 ? 's' : ''} (prénom et nom requis).');
    }
    if (datesProposees.isEmpty) {
      erreurs.add('Propose au moins une date pour le pacte.');
    }
    return erreurs;
  }

  bool _peutValider() => _erreursValidation().isEmpty;

  Future<void> _ouvrirLienRestaurant(String lien) async {
    await launchUrl(Uri.parse(lien), webOnlyWindowName: '_blank');
  }

  String get _nomCompletDestinataire {
    final prenom = prenomDestinataireController.text.trim();
    final nom = nomDestinataireController.text.trim();
    return [prenom, nom].where((s) => s.isNotEmpty).join(' ');
  }

  Future<void> _inviterParSms() async {
    final numero = telephoneDestinataireController.text.trim();
    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne le numéro de téléphone pour inviter par SMS.')),
      );
      return;
    }
    final prenom = prenomDestinataireController.text.trim();
    final salutation = prenom.isNotEmpty ? 'Hello $prenom' : 'Hello';
    final message = "$salutation, je t'invite à faire un pacte avec moi sur l'application Le Pacte !\n"
        "Le principe : on trouve une date qui nous convient pour dîner ensemble mais on a pas le "
        "droit d'en parler jusqu'au jour J. Si jamais on est finalement pas dispo, on a le droit de "
        "faire appel à des remplaçants. Je te laisse en découvrir plus en téléchargeant l'app :) "
        "$lienTelechargementApp";
    final numeroPropre = numero.replaceAll(RegExp(r'\s+'), '');
    await launchUrl(Uri.parse('sms:$numeroPropre?body=${Uri.encodeComponent(message)}'));
  }

  Future<void> _creerPacte(Restaurant restau) async {
    setState(() {
      enCours = true;
      erreur = null;
    });
    try {
      await PacteRepository.creerPacte(
        type: type,
        datesProposees: List.of(datesProposees),
        initiateurId: AppStore.moi.id,
        initiateurNom: AppStore.moi.nomComplet,
        destinataireNom: _nomCompletDestinataire,
        destinataireTelephone: telephoneDestinataireController.text.trim(),
        remplacantsInitiateur: remplacants,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = "Impossible d'envoyer le pacte pour le moment. Réessaie.";
      });
    }
  }
}
