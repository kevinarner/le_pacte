// SMOKE — le cœur de Swend en un parcours : création, scellement, personne
// de confiance, "Un imprévu ?", acceptation, confidentialité de David.
import { CONTACTS_SANS_COMPTE as C, COMPTES } from '../lib/config.mjs';
import * as A from '../lib/actions.mjs';
import { sql } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

export default {
  nom: 'smoke_parcours_principal',
  titre: 'Création → scellement → Un imprévu ? → Kevin prend la place',
  suites: ['smoke', 'full'],
  fixture: 'comptes',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();

    await ex.etape('1-2. Eliot crée un Swend avec David, Kevin et Tom en personnes de confiance', async () => {
      await A.creerSwend(eliot, { prenom: 'David', nom: 'Schlang', tel: COMPTES.david.tel,
        personnes: [{ prenom: 'Kevin', nom: 'Arner', tel: COMPTES.kevin.tel }, C.tom] });
      await ex.verifier('création du Swend (en base, destinataire rattaché au compte de David)',
        () => sql(`select count(*) from pactes where destinataire_id = '${COMPTES.david.id}'`) === '1');
      await A.ouvrirMesSwends(eliot);
      await ex.verifierTexte(eliot, /Swend avec David Schlang\s+(En attente|Attente)/, 'Eliot : "En attente" de David');
    });

    await ex.etape('3-4. David reçoit, choisit la date et accepte : Swend scellé', async () => {
      await A.ouvrirMesSwends(david);
      await ex.verifierTexte(david, /Swend avec Eliot Martin\s+À vous de répondre/, 'David : "À vous de répondre"');
      await A.accepterSwend(david, { avec: /Swend avec Eliot/, personnes: [C.leo, C.nina] });
      await ex.verifier('scellement (statut confirmé en base)', () => sql('select statut from pactes') === 'confirme');
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Scellé', 'Eliot : Swend "Scellé"');
      ex.memo.david = await photoDavid(ex);
    });

    await ex.etape('5-6. Kevin voit "On compte sur toi", sans Swend à venir', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, 'ON COMPTE SUR TOI', 'Kevin voit "On compte sur toi"');
      await ex.verifierTexte(kevin, 'Eliot compte sur toi pour un Swend', 'Kevin : "Eliot compte sur toi pour un Swend"');
      await ex.verifierTexte(kevin, /Mes Swends\s+0 à venir/, 'Kevin : ne compte pas comme Swend à venir (0 à venir)');
    });

    await ex.etape('7-8. Eliot : Un imprévu ? → Lui demander à Kevin', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await ex.verifierTexte(eliot, 'En attente', 'demande envoyée (Kevin "En attente")');
    });

    await ex.etape('9-11. Kevin voit la demande, l\'ouvre et accepte', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, "UNE DEMANDE T'ATTEND", 'Kevin voit "Une demande t\'attend"');
      await ex.verifierTexte(kevin, 'Eliot a un imprévu', 'Kevin : "Eliot a un imprévu"');
      await A.repondre(kevin, true);
      await ex.verifier('Kevin accepte (sélectionné en base)', () => sql(`select selectionne from remplacants where prenom = 'Kevin'`) === 't');
    });

    await ex.etape('12. Eliot voit "Kevin prendra votre place"', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Kevin prendra votre place', 'Eliot voit "Kevin prendra votre place"');
    });

    await ex.etape('13-14. Kevin prend la place d\'Eliot, et le Swend compte pour lui', async () => {
      await kevin.accueil();
      await ex.verifierTexte(kevin, "Tu prends la place d'Eliot", 'Kevin voit "Tu prends la place d\'Eliot"');
      await ex.verifierTexte(kevin, /Mes Swends\s+1 à venir/, 'Kevin : 1 Swend à venir');
      await ex.verifierTexte(kevin, 'TON PROCHAIN SWEND', 'Kevin : "Ton prochain Swend"');
    });

    await ex.etape('15-16. Eliot garde "Écrire à Kevin" et "Discuter"', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Écrire à Kevin', 'Eliot conserve "Écrire à Kevin"');
      await eliot.cliquer('Discuter');
      await ex.verifierTexte(eliot, 'Discuter avec…', 'Eliot conserve "Discuter"');
      await ex.verifierTexte(eliot, 'Kevin Arner', '"Discuter" propose Kevin (a un compte)');
      await ex.verifierAbsent(eliot, 'Tom Petit', '"Discuter" ne propose pas Tom (sans compte)');
    });

    await ex.etape('17. David ne voit aucun indice du remplacement', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
