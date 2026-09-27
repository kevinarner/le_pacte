// DOUBLE REMPLACEMENT — Eliot ET David se font remplacer : le Swend est
// annulé pour tout le monde, avec le message dédié.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';

export default {
  nom: 'double_remplacement',
  titre: 'Eliot et David sont tous deux remplacés : Swend annulé',
  suites: ['full'],
  fixture: 'scelle_double',
  async executer(ex) {
    const eliot = await ex.eliot();
    const david = await ex.david();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();

    await ex.etape('Kevin prend la place d\'Eliot', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await A.repondre(kevin, true);
      await ex.verifier('Kevin sélectionné, Swend toujours scellé',
        () => demande(FICHES.kevin) === 'acceptee|t' && sql('select statut from pactes') === 'confirme',
        { obtenu: () => `${demande(FICHES.kevin)} / ${sql('select statut from pactes')}` });
    });

    await ex.etape('Sylvain prend la place de David', async () => {
      await A.ouvrirImprevu(david, /Swend avec Eliot/);
      await A.demander(david, 'Sylvain Landiech');
      await A.repondre(sylvain, true);
      await ex.verifier('Swend annulé pour double absence',
        () => sql('select statut from pactes') === 'annuleDoubleAbsence', { obtenu: () => sql('select statut from pactes') });
    });

    await ex.etape('Eliot et David voient "Swend annulé"', async () => {
      for (const [a, autre] of [[eliot, 'David'], [david, 'Eliot']]) {
        await A.ouvrirSwend(a, new RegExp(`Swend avec ${autre}`));
        await ex.verifierTexte(a, 'Swend annulé', `${a.compte.prenom} : "Swend annulé"`);
        await ex.verifierTexte(a, "Vous avez chacun dû faire appel à quelqu'un pour vous remplacer", `${a.compte.prenom} : message de double remplacement`);
        await a.accueil();
        await ex.verifierTexte(a, /Mes Swends\s+0 à venir/, `${a.compte.prenom} : 0 à venir`);
        await ex.verifierAbsent(a, 'TON PROCHAIN SWEND', `${a.compte.prenom} : plus de "Ton prochain Swend"`);
      }
    });

    await ex.etape('Kevin et Sylvain : le Swend est annulé', async () => {
      for (const [a, titulaire, autre] of [[kevin, 'Eliot', 'David'], [sylvain, 'David', 'Eliot']]) {
        await a.accueil();
        await ex.verifierTexte(a, /Mes Swends\s+0 à venir/, `${a.compte.prenom} : 0 à venir`);
        await ex.verifierAbsent(a, 'TON PROCHAIN SWEND', `${a.compte.prenom} : plus de "Ton prochain Swend"`);
        await A.ouvrirSwend(a, new RegExp(`Swend ${A.deNom(titulaire)} avec ${autre}`));
        await ex.verifierTexte(a, 'Ce Swend a été annulé.', `${a.compte.prenom} : "Ce Swend a été annulé."`);
        await ex.verifier(`${a.compte.prenom} : plus de désistement possible`, async () => (await a.nombreDeBoutons('Je ne peux finalement plus venir')) === 0);
      }
    });

    await ex.etape('Aucune fuite de nom entre les deux côtés', async () => {
      await A.ouvrirSwend(david, /Swend avec Eliot/);
      await ex.verifierAbsent(david, 'Kevin', 'David ne sait pas que c\'était Kevin');
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierAbsent(eliot, 'Sylvain', 'Eliot ne sait pas que c\'était Sylvain');
    });
  },
};
