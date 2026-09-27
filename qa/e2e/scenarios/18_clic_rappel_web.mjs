// CLIC SUR UN RAPPEL (WEB, D-021) — la notification web ouvre l'app avec
// ?rappel=<pacte_id> (lien de l'Edge Function) ; après connexion, l'app
// demande la destination à la base selon l'état ACTUEL du Swend :
// titulaire qui cherche → « Un imprévu ? », sinon la fiche, sans accès →
// l'accueil. L'adresse est ensuite nettoyée (un rechargement ne rouvre rien).
import * as A from '../lib/actions.mjs';
import { config } from '../lib/config.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';

const IMPREVU = /Qui peut prendre votre place|Personne n'est encore prévu|Aucune des personnes prévues|prendra votre place\./;

// Comme un clic sur la notification : nouvelle page sur le lien, connexion.
async function ouvrirLien(a, url) {
  await a.page.goto(url, { waitUntil: 'load' });
  await a.activerAccessibilite();
  await a.page.getByRole('textbox').first().waitFor({ timeout: 15000 });
  await a.saisir(a.page.getByRole('textbox').nth(0), a.compte.email);
  await a.saisir(a.page.getByRole('textbox').nth(1), config.QA_MOT_DE_PASSE);
  await a.cliquer('Se connecter');
  await a.attendreCalme();
}

export default {
  nom: 'clic_rappel_web',
  titre: 'Clic sur un rappel (web) : Un imprévu ?, fiche ou accueil selon l\'état actuel',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    const lien = `${config.appUrl}/?rappel=${sql('select id from pactes')}`;

    await ex.etape('David (rien de particulier) : la fiche du Swend', async () => {
      await ouvrirLien(david, lien);
      await ex.verifierTexte(david, 'Swend avec Eliot', 'David : fiche « Swend avec Eliot »');
      await ex.verifierAbsent(david, IMPREVU, 'David : pas « Un imprévu ? »');
      await ex.verifier('adresse nettoyée (plus de ?rappel)', () => !david.page.url().includes('rappel='), { obtenu: () => david.page.url() });
    });

    await ex.etape('Eliot cherche quelqu\'un : « Un imprévu ? »', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await ouvrirLien(eliot, lien);
      await ex.verifierTexte(eliot, IMPREVU, 'Eliot : écran « Un imprévu ? »');
      await eliot.retour();
      await ex.verifierTexte(eliot, 'Swend avec David', 'Eliot : retour → fiche du Swend');
    });

    await ex.etape('Kevin accepte : Eliot et Kevin arrivent sur la fiche', async () => {
      await A.repondre(kevin, true);
      await ex.verifier('Kevin sélectionné', () => demande(FICHES.kevin) === 'acceptee|t', { obtenu: () => demande(FICHES.kevin) });
      await ouvrirLien(eliot, lien);
      await ex.verifierTexte(eliot, 'Swend avec David', 'Eliot (remplacé) : fiche du Swend');
      await ex.verifierAbsent(eliot, IMPREVU, 'Eliot (remplacé) : plus « Un imprévu ? »');
      await ouvrirLien(kevin, lien);
      await ex.verifierTexte(kevin, "Swend d'Eliot avec David", 'Kevin (remplaçant) : fiche du Swend');
    });

    await ex.etape('Sylvain (aucun accès) : reste sur l\'accueil', async () => {
      await ouvrirLien(sylvain, lien);
      await sylvain.accueilCharge();
      await sylvain.page.waitForTimeout(1500);
      await sylvain.attendreCalme();
      await ex.verifier('Sylvain : accueil, aucune fiche ouverte', () => sylvain.estSurAccueil());
    });

    await ex.etape('Rechargement : le rappel ne se rouvre pas', async () => {
      await ouvrirLien(eliot, eliot.page.url());
      await eliot.accueilCharge();
      await eliot.page.waitForTimeout(1500);
      await eliot.attendreCalme();
      await ex.verifier('Eliot : accueil après rechargement', () => eliot.estSurAccueil());
    });
  },
};
