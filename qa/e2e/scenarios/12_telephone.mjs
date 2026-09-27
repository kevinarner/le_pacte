// TÉLÉPHONE — formats acceptés (0033, +33, points, espaces), numéros
// invalides, son propre numéro, doublons, rattachement aux comptes quel
// que soit le format, statut "déjà sur Swend".
import { sql } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';
import * as A from '../lib/actions.mjs';

const suivantActif = async (a) => !(await a.page.getByRole('button', { name: 'Suivant', exact: true }).isDisabled());

export default {
  nom: 'telephone',
  titre: 'Formats de numéro, refus, doublons, rattachement aux comptes',
  suites: ['full'],
  fixture: 'comptes',
  async executer(ex) {
    const eliot = await ex.eliot();

    await ex.etape('Étape "Avec qui ?" : numéros refusés', async () => {
      await eliot.cliquer('Créer un Swend');
      await eliot.taper('Prénom', 'David');
      await eliot.taper('Nom', 'Schlang');
      await eliot.taper('Numéro de mobile', '01 23 45 67 89');
      await ex.verifierTexte(eliot, 'Numéro de mobile invalide', 'fixe "01 23 45 67 89" : invalide');
      await ex.verifier('"Suivant" désactivé (invalide)', async () => !(await suivantActif(eliot)));
      await eliot.taper('Numéro de mobile', '06 70 41');
      await ex.verifierTexte(eliot, 'Numéro de mobile invalide', 'trop court : invalide');
      await eliot.taper('Numéro de mobile', '+33 6 01 02 03 04');
      await ex.verifierTexte(eliot, "C'est ton propre numéro.", 'son propre numéro (autre format) : refusé');
      await ex.verifier('"Suivant" désactivé (son numéro)', async () => !(await suivantActif(eliot)));
    });

    await ex.etape('Format "0033" : David reconnu', async () => {
      await eliot.taper('Numéro de mobile', '0033 6 02 03 04 05');
      await ex.verifierTexte(eliot, 'David est déjà sur Swend', '"David est déjà sur Swend"');
      await ex.verifier('"Suivant" actif', () => suivantActif(eliot));
      await eliot.cliquer('Suivant');
      await eliot.cliquer('Ajouter une date');
      await eliot.cliquer('OK');
      await eliot.cliquer('Suivant');
    });

    await ex.etape('Personnes de confiance : doublons et numéros interdits', async () => {
      await eliot.taper('Prénom', 'Kevin', 0);
      await eliot.taper('Nom', 'Arner', 0);
      await eliot.taper('Numéro de mobile', '+33670419277', 0);
      await A.statutAffiche(eliot, 'Kevin');
      await ex.verifierTexte(eliot, 'Kevin est déjà sur Swend', 'Kevin (+33…) : "déjà sur Swend"');
      await eliot.taper('Prénom', 'Kev', 1);
      await eliot.taper('Nom', 'Arner', 1);
      await eliot.taper('Numéro de mobile', '06 70 41 92 77', 1);
      await ex.verifierTexte(eliot, 'Cette personne est déjà dans la liste.', 'même numéro, autre format : doublon');
      await eliot.taper('Numéro de mobile', '06.02.03.04.05', 1);
      await ex.verifierTexte(eliot, "C'est le numéro de David, avec qui tu fais ce Swend.", 'numéro de David : refusé');
      await eliot.taper('Numéro de mobile', '0601020304', 1);
      await ex.verifierTexte(eliot, "C'est ton propre numéro.", 'son propre numéro : refusé');
      await ex.verifier('"Envoyer le Swend" désactivé', async () => eliot.page.getByRole('button', { name: 'Envoyer le Swend', exact: true }).isDisabled());
      await eliot.taper('Prénom', 'Tom', 1);
      await eliot.taper('Nom', 'Petit', 1);
      await eliot.taper('Numéro de mobile', '07.11.22.33.44', 1);
      await A.statutAffiche(eliot, 'Tom');
      await ex.verifierTexte(eliot, "Tom n'a pas encore Swend", 'Tom : "n\'a pas encore Swend"');
      await eliot.cliquer('Ajouter une personne');
      await eliot.taper('Prénom', 'Sylvain', 2);
      await eliot.taper('Nom', 'Landiech', 2);
      await eliot.taper('Numéro de mobile', '0033655443322', 2);
      await A.statutAffiche(eliot, 'Sylvain');
      await ex.verifierTexte(eliot, 'Sylvain est déjà sur Swend', 'Sylvain (0033…) : "déjà sur Swend"');
      await eliot.cliquer('Envoyer le Swend');
      await eliot.attendreTexte('Bonjour Eliot');
    });

    await ex.etape('En base : numéros canoniques et comptes rattachés', async () => {
      await ex.verifier('David rattaché (saisi en 0033)',
        () => sql(`select destinataire_id from pactes`) === COMPTES.david.id, { obtenu: () => sql('select destinataire_id from pactes') });
      const fiches = () => sql(`select string_agg(r.prenom || '=' || normaliser_telephone(r.telephone) || ':' || coalesce(p.prenom, '-'), ', ' order by r.prenom)
                                from remplacants r left join profiles p on p.id = r.profil_id`);
      await ex.verifier('numéros normalisés (E.164) et rattachés aux bons comptes',
        () => fiches() === 'Kevin=+33670419277:Kevin, Sylvain=+33655443322:Sylvain, Tom=+33711223344:-', { obtenu: fiches });
    });

    await ex.etape('Kevin retrouve le Swend malgré un format différent', async () => {
      const david = await ex.david();
      await A.accepterSwend(david, { avec: /Swend avec Eliot/, personnes: [{ prenom: 'Léo', nom: 'Blanc', tel: '07 22 33 44 55' }, { prenom: 'Nina', nom: 'Roy', tel: '07 33 44 55 66' }] });
      const kevin = await ex.kevin();
      await kevin.accueil();
      await ex.verifierTexte(kevin, 'Eliot compte sur toi pour un Swend', 'Kevin : "Eliot compte sur toi"');
    });
  },
};
