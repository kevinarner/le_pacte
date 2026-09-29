// PERSONNES DE CONFIANCE — liste, statuts Swend, ajout au-delà de 5,
// doublons refusés, retrait, "Discuter" limité aux personnes sur Swend.
import { COMPTES } from '../lib/config.mjs';
import * as A from '../lib/actions.mjs';
import { sql } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

// Fiches actives : une personne retirée est archivée, pas supprimée (D-023a).
const nbCoteEliot = () => sql(`select count(*) from remplacants where cote = 'initiateur' and retire_le is null`);

export default {
  nom: 'personnes_de_confiance',
  titre: 'Liste : ordre, statuts, > 5 personnes, doublons, retrait, Discuter',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Fiche : personnes disponibles, comptes Swend d\'abord', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, /(Kevin, Sylvain|Sylvain, Kevin), Tom/, 'Eliot : Kevin et Sylvain (comptes) avant Tom');
      await ex.verifierTexte(eliot, 'Ces personnes pourront prendre votre place', 'texte au pluriel');
      await ex.verifier('boutons "Modifier ma liste" et "Discuter" présents',
        async () => (await eliot.nombreDeBoutons('Modifier ma liste')) === 1 && (await eliot.nombreDeBoutons('Discuter')) === 1);
      await ex.verifier('"Un imprévu ?" visible sur la fiche', async () => (await eliot.nombreDeBoutons('Un imprévu ?')) === 1);
    });

    await ex.etape('Modifier ma liste : statut Swend de chaque personne', async () => {
      await A.ouvrirModifierMaListe(eliot);
      await ex.verifierTexte(eliot, 'Kevin est déjà sur Swend', 'Kevin : "est déjà sur Swend"');
      await ex.verifierTexte(eliot, 'Sylvain est déjà sur Swend', 'Sylvain : "est déjà sur Swend"');
      await ex.verifierTexte(eliot, "Tom n'a pas encore Swend", 'Tom : "n\'a pas encore Swend"');
      await ex.verifier('"Envoyer l\'invitation" seulement pour Tom', async () => (await eliot.nombreDeBoutons("Envoyer l'invitation")) === 1);
      await ex.verifier('aucun "Discuter" sur les cartes', async () => (await eliot.nombreDeBoutons('Discuter')) === 0);
      await ex.verifier('"Retirer" sur chaque carte', async () => (await eliot.nombreDeBoutons('Retirer')) === 3);
    });

    await ex.etape('Ajout de 3 personnes : 6 au total (pas de limite globale de 5)', async () => {
      await A.ajouterPersonnes(eliot, [
        { prenom: 'Paul', nom: 'Durand', tel: '06 12 34 56 78' },
        { prenom: 'Zoé', nom: 'Moreau', tel: '06 23 45 67 89' },
        { prenom: 'Hugo', nom: 'Laurent', tel: '06 34 56 78 90' },
      ]);
      await ex.verifier('6 personnes côté Eliot en base', () => nbCoteEliot() === '6', { obtenu: nbCoteEliot });
      await ex.verifierTexte(eliot, 'Zoé Moreau', 'Zoé apparaît dans "Personnes prévues"');
    });

    await ex.etape('Doublons et numéros interdits refusés', async () => {
      await eliot.cliquer('Ajouter une personne');
      await eliot.taper('Prénom', 'Tom');
      await eliot.taper('Nom', 'Petit');
      await eliot.taper('Numéro de mobile', '+33 7 11 22 33 44');
      await ex.verifierTexte(eliot, 'Cette personne est déjà prévue.', 'Tom (autre format) : "déjà prévue"');
      await ex.verifier('"Enregistrer" désactivé', async () => await eliot.page.getByRole('button', { name: 'Enregistrer', exact: true }).isDisabled());
      await eliot.taper('Numéro de mobile', '0601020304');
      await ex.verifierTexte(eliot, "C'est ton propre numéro.", 'son propre numéro : refusé');
      await eliot.taper('Prénom', 'David');
      await eliot.taper('Nom', 'Schlang');
      await eliot.taper('Numéro de mobile', '06 02 03 04 05');
      await eliot.cliquer('Enregistrer');
      await ex.verifierTexte(eliot, 'Une des personnes participe déjà à ce Swend', 'David (autre participant) : refusé par la base');
      await ex.verifier('toujours 6 personnes côté Eliot', () => nbCoteEliot() === '6', { obtenu: nbCoteEliot });
    });

    await ex.etape('Retirer Zoé', async () => {
      await eliot.accueil({ rafraichir: false });
      await A.retirerPersonne(eliot, 'Zoé Moreau');
      await ex.verifier('Zoé retirée en base (5 personnes)', () => nbCoteEliot() === '5', { obtenu: nbCoteEliot });
      await ex.verifier('Zoé archivée, pas supprimée (D-023a)',
        () => sql(`select count(*) from remplacants where prenom = 'Zoé' and retire_le is not null`) === '1');
      await ex.verifierAbsent(eliot, 'Zoé Moreau', 'Zoé n\'apparaît plus');
    });

    await ex.etape('"Discuter" ne propose que les personnes qui ont un compte', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await eliot.cliquer('Discuter');
      await ex.verifierTexte(eliot, 'Discuter avec…', 'feuille "Discuter avec…"');
      await ex.verifierTexte(eliot, 'Kevin Arner', 'Kevin proposé');
      await ex.verifierTexte(eliot, 'Sylvain Landiech', 'Sylvain proposé');
      for (const n of ['Tom Petit', 'Paul Durand', 'Hugo Laurent']) await ex.verifierAbsent(eliot, n, `${n} non proposé (sans compte)`);
    });

    await ex.etape('David ne voit rien de la liste d\'Eliot', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david, { nomsInterdits: ['Kevin', 'Sylvain', 'Tom', 'Paul', 'Zoé', 'Hugo'] });
      await ex.verifier('aucune notification pour Kevin ou Sylvain (aucune demande envoyée)',
        () => sql(`select count(*) from notifications_log where profile_id in ('${COMPTES.kevin.id}', '${COMPTES.sylvain.id}')`) === '0');
    });
  },
};
