// AJOUT PENDANT UN IMPRÉVU — "Ajouter quelqu'un" depuis Un imprévu ? :
// la personne ajoutée reçoit directement la demande ; refus des doublons,
// de l'autre participant et des numéros invalides.
import * as A from '../lib/actions.mjs';
import { sql } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

async function ajouterDepuisImprevu(ex, eliot, { prenom, nom, tel }, { valider = true } = {}) {
  await eliot.cliquer("Ajouter quelqu'un");
  await eliot.attendreTexte('Cette personne recevra directement votre demande');
  await eliot.taper('Prénom', prenom);
  await eliot.taper('Nom', nom);
  await eliot.taper('Numéro de mobile', tel);
  await A.statutAffiche(eliot, prenom);
  if (valider) await eliot.cliquer('Lui demander de prendre ma place');
}
const ficheDe = (prenom) => sql(`select coalesce(demande_statut, '') || '|' || (profil_id is not null) from remplacants where cote = 'initiateur' and prenom = '${prenom}'`);

export default {
  nom: 'ajout_pendant_imprevu',
  titre: "Un imprévu ? → Ajouter quelqu'un (compte, sans compte, refus)",
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Préparation : Eliot retire Sylvain de sa liste', async () => {
      await A.retirerPersonne(eliot, 'Sylvain Landiech');
      await ex.verifier('Sylvain retiré', () => ficheDe('Sylvain') === '');
    });

    await ex.etape('Ajout de Sylvain (a un compte) : demande envoyée directement', async () => {
      await eliot.accueil({ rafraichir: false });
      await A.ouvrirImprevu(eliot);
      await ajouterDepuisImprevu(ex, eliot, { prenom: 'Sylvain', nom: 'Landiech', tel: '06.55.44.33.22' }, { valider: false });
      await ex.verifierTexte(eliot, 'Sylvain est déjà sur Swend', 'formulaire : "Sylvain est déjà sur Swend"');
      await eliot.cliquer('Lui demander de prendre ma place');
      await ex.verifier('Sylvain ajouté, rattaché à son compte, demande envoyée', () => ficheDe('Sylvain') === 'envoyee|true', { obtenu: () => ficheDe('Sylvain') });
      await ex.verifierTexte(eliot, /Sylvain Landiech\s+En attente/, 'Sylvain : "En attente"');
      await sylvain.accueil();
      await ex.verifierTexte(sylvain, "UNE DEMANDE T'ATTEND", 'Sylvain : "Une demande t\'attend"');
    });

    await ex.etape('Ajout de Paul (sans compte) : demande + proposition de message', async () => {
      await ajouterDepuisImprevu(ex, eliot, { prenom: 'Paul', nom: 'Durand', tel: '06 12 34 56 78' }, { valider: false });
      await ex.verifierTexte(eliot, "Paul n'a pas encore Swend", 'formulaire : "Paul n\'a pas encore Swend"');
      await eliot.cliquer('Lui demander de prendre ma place');
      await ex.verifierTexte(eliot, 'Demande envoyée', 'boîte "Demande envoyée"');
      await eliot.cliquer('Envoyer le message', { dernier: true });
      await eliot.cliquer('Messages');
      await ex.verifier('message urgent vers +33612345678', () => (eliot.liensOuverts.at(-1) || '').startsWith('sms:+33612345678?body='),
        { obtenu: () => eliot.liensOuverts.at(-1) });
      await ex.verifier('Paul : demande envoyée, sans compte', () => ficheDe('Paul') === 'envoyee|false', { obtenu: () => ficheDe('Paul') });
    });

    await ex.etape('Refus : autre participant, doublon, numéro invalide', async () => {
      await ajouterDepuisImprevu(ex, eliot, { prenom: 'David', nom: 'Schlang', tel: '06 02 03 04 05' });
      await ex.verifierTexte(eliot, 'Cette personne participe déjà à ce Swend', 'David : "participe déjà à ce Swend"');
      await ajouterDepuisImprevu(ex, eliot, { prenom: 'Kevin', nom: 'Arner', tel: '+33 6 70 41 92 77' });
      await ex.verifierTexte(eliot, 'Cette personne est déjà dans votre liste.', 'Kevin (autre format) : "déjà dans votre liste"');
      await ajouterDepuisImprevu(ex, eliot, { prenom: 'Zoé', nom: 'Moreau', tel: '06 12' }, { valider: false });
      await ex.verifierTexte(eliot, 'Numéro de mobile invalide', 'numéro invalide signalé');
      await ex.verifier('bouton de validation désactivé',
        async () => eliot.page.getByRole('button', { name: 'Lui demander de prendre ma place', exact: true }).isDisabled());
      await eliot.page.keyboard.press('Escape');
      await ex.verifier('aucune fiche en trop (Kevin, Tom, Sylvain, Paul)',
        () => sql(`select string_agg(prenom, ',' order by prenom) from remplacants where cote = 'initiateur'`) === 'Kevin,Paul,Sylvain,Tom');
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david, { nomsInterdits: ['Kevin', 'Sylvain', 'Tom', 'Paul'] });
    });
  },
};
