import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants.dart';
import '../../models/remplacant.dart';
import '../../models/restaurant.dart';
import '../../models/type_repas.dart';
import '../../services/app_store.dart';
import '../../services/contact_picker_service.dart';
import '../../services/pacte_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dates_form.dart';
import '../../widgets/remplacants_form.dart';
import '../contact/suggestion_restaurant_screen.dart';

const _minimumRemplacants = 2;
const _nombreEtapes = 3;

/// Création d'un pacte en 3 étapes courtes (avec qui, où et quand, tes
/// remplaçants) plutôt qu'un seul long formulaire — chaque étape se
/// valide avant de passer à la suivante.
class CreerPacteScreen extends StatefulWidget {
  const CreerPacteScreen({super.key});

  @override
  State<CreerPacteScreen> createState() => _CreerPacteScreenState();
}

class _CreerPacteScreenState extends State<CreerPacteScreen> {
  int etape = 0;

  TypeRepas type = TypeRepas.diner;
  final List<DateTime> datesProposees = [];
  final prenomDestinataireController = TextEditingController();
  final nomDestinataireController = TextEditingController();
  final telephoneDestinataireController = TextEditingController();
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
                const Icon(Icons.error_outline, color: AppColors.erreur, size: 32),
                const SizedBox(height: 12),
                Text(
                  "Impossible de charger le restaurant.\n$erreurChargement",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.erreur, fontSize: 12),
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
      appBar: AppBar(
        leading: etape > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => etape -= 1),
              )
            : null,
        title: const Text('Nouveau pacte'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _indicateurEtapes(),
          const SizedBox(height: 16),
          if (etape == 0) ..._etapeAvecQui(),
          if (etape == 1) ..._etapeOuEtQuand(restau),
          if (etape == 2) ..._etapeRemplacants(),
          const SizedBox(height: 24),
          if (erreur != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(erreur!, style: const TextStyle(color: AppColors.erreur)),
            ),
          ],
          FilledButton(
            onPressed: !enCours && _peutValiderEtape(etape) ? _suivant : null,
            child: enCours
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(etape == _nombreEtapes - 1 ? 'Envoyer le pacte' : 'Suivant'),
          ),
        ],
      ),
    );
  }

  Widget _indicateurEtapes() {
    return Row(
      children: [
        for (var i = 0; i < _nombreEtapes; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= etape ? AppColors.accent : AppColors.outline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _etapeAvecQui() {
    return [
      Text('Avec qui ?', style: Theme.of(context).textTheme.titleLarge),
      Text('Étape 1 sur $_nombreEtapes', style: const TextStyle(color: AppColors.texteAttenue)),
      const SizedBox(height: 16),
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
      if (ContactPickerService.disponible) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _choisirDansLesContacts,
          icon: const Icon(Icons.contacts_outlined, size: 18),
          label: const Text('Choisir dans mes contacts'),
        ),
      ],
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
    ];
  }

  Future<void> _choisirDansLesContacts() async {
    final contact = await ContactPickerService.choisirContact();
    if (contact == null || !mounted) return;
    final nomComplet = contact['nom'] ?? '';
    final parts = nomComplet.trim().split(RegExp(r'\s+'));
    setState(() {
      if (parts.isNotEmpty && parts.first.isNotEmpty) {
        prenomDestinataireController.text = parts.first;
        nomDestinataireController.text = parts.skip(1).join(' ');
      }
      if ((contact['telephone'] ?? '').isNotEmpty) {
        telephoneDestinataireController.text = contact['telephone']!;
      }
    });
  }

  List<Widget> _etapeOuEtQuand(Restaurant restau) {
    return [
      Text('Où et quand ?', style: Theme.of(context).textTheme.titleLarge),
      Text('Étape 2 sur $_nombreEtapes', style: const TextStyle(color: AppColors.texteAttenue)),
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
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Restaurant proposé',
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(height: 2),
              Text(restau.nom, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _ouvrirLienRestaurant(restau.lien),
                child: Text(
                  restau.lien,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 4),
      RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black54),
          children: [
            const TextSpan(
              text: "D'autres restaurants vous seront bientôt proposés, "
                  'vous pouvez nous en suggérer : ',
            ),
            TextSpan(
              text: 'ici',
              style: const TextStyle(
                color: AppColors.accent,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()..onTap = _suggererUnRestaurant,
            ),
          ],
        ),
      ),
    ];
  }

  void _suggererUnRestaurant() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SuggestionRestaurantScreen()),
    );
  }

  List<Widget> _etapeRemplacants() {
    return [
      Text('Tes remplaçants', style: Theme.of(context).textTheme.titleLarge),
      Text('Étape 3 sur $_nombreEtapes · minimum $_minimumRemplacants',
          style: const TextStyle(color: AppColors.texteAttenue)),
      const SizedBox(height: 4),
      const Text(
        "Propres à ce pacte : cette liste ne sera jamais visible par la personne avec qui "
        "tu fais le pacte.",
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
    ];
  }

  bool _peutValiderEtape(int e) {
    switch (e) {
      case 0:
        return prenomDestinataireController.text.trim().isNotEmpty &&
            nomDestinataireController.text.trim().isNotEmpty &&
            telephoneDestinataireController.text.trim().isNotEmpty;
      case 1:
        return datesProposees.isNotEmpty;
      case 2:
        return remplacants.where((r) => r.estRempli).length >= _minimumRemplacants;
      default:
        return false;
    }
  }

  void _suivant() {
    if (etape < _nombreEtapes - 1) {
      setState(() => etape += 1);
      return;
    }
    _creerPacte(restaurant!);
  }

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
    final message = "$salutation, je t'invite à faire un pacte avec moi sur l'application Pakt !\n"
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        enCours = false;
        erreur = "Impossible d'envoyer le pacte pour le moment.\n$e";
      });
    }
  }
}
