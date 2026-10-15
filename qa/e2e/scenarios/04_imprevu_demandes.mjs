// UN IMPRÉVU ? (D-027) — choix de plusieurs personnes, bouton adaptatif,
// confirmations, envoi groupé, attente, « Je peux finalement venir », refus
// et « Personne n'a pu prendre ta place. », fiche, confidentialité de David.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';
import { COMPTES } from '../lib/config.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const notifs = (nom) => sql(`select coalesce(string_agg(titre || '|' || corps, ' ## ' order by id), '') from notifications_log where profile_id = '${COMPTES[nom].id}'`);
const cases = (a) => a.page.getByRole('checkbox').count();

export default {
  nom: 'imprevu_demandes',
  titre: 'Choix multiple, envoi groupé, Je peux finalement venir, refus, Personne n’a pu',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);

    await ex.etape('Écran « Un imprévu ? » : choisir parmi ses remplaçants', async () => {
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Tu ne peux plus être là ?', 'titre « Tu ne peux plus être là ? »');
      await ex.verifierTexte(eliot, 'Sollicite l’un de tes remplaçants :)', 'sous-titre « Sollicite l’un de tes remplaçants :) »');
      await ex.verifier('une case par personne prévue (Kevin, Sylvain, Tom)', async () => (await cases(eliot)) === 3);
      await ex.verifierTexte(eliot, 'Tom n’a pas encore Swend', 'Tom : « n’a pas encore Swend »');
      await ex.verifier('comptes Swend listés avant Tom',
        async () => (await eliot.positionY('Tom Petit')) > Math.max(await eliot.positionY('Kevin Arner'), await eliot.positionY('Sylvain Landiech')));
      await ex.verifier('aucun bouton d’envoi tant que personne n’est choisi',
        async () => !(await eliot.voit(/Demander à |Envoyer \d demandes/)));
      await ex.verifier('plus aucune annulation demande par demande ni « Lui demander »',
        async () => (await eliot.nombreDeBoutons('Annuler la demande')) === 0 && (await eliot.nombreDeBoutons('Lui demander')) === 0);
    });

    await ex.etape('Bouton adaptatif, confirmation à plusieurs, envoi groupé', async () => {
      await A.cocher(eliot, 'Kevin Arner');
      await ex.verifier('une personne : « Demander à Kevin »', async () => (await eliot.nombreDeBoutons('Demander à Kevin')) === 1);
      await A.cocher(eliot, 'Sylvain Landiech');
      await ex.verifier('deux personnes : « Envoyer 2 demandes »', async () => (await eliot.nombreDeBoutons('Envoyer 2 demandes')) === 1);
      await eliot.cliquer('Envoyer 2 demandes');
      await ex.verifierTexte(eliot, 'Envoyer la demande ?', 'confirmation : « Envoyer la demande ? »');
      await ex.verifierTexte(eliot, 'La première personne qui accepte prendra ta place.', 'confirmation : première acceptation');
      await ex.verifierTexte(eliot, 'Une fois ta place prise, tu ne pourras plus revenir en arrière.', 'confirmation : pas de retour en arrière');
      await eliot.cliquer('Retour');
      await ex.verifier('« Retour » : rien n’est parti', () => demande(FICHES.kevin) === '|f' && demande(FICHES.sylvain) === '|f');
      await eliot.cliquer('Envoyer 2 demandes');
      await eliot.cliquer('Envoyer les demandes');
      await ex.verifier('deux demandes « envoyee » en base',
        () => demande(FICHES.kevin) === 'envoyee|f' && demande(FICHES.sylvain) === 'envoyee|f',
        { obtenu: () => `${demande(FICHES.kevin)} / ${demande(FICHES.sylvain)}` });
      await ex.verifierTexte(eliot, 'C’est envoyé.', 'attente : « C’est envoyé. »');
      await ex.verifierTexte(eliot, 'La première personne qui accepte prendra ta place.', 'attente : sous-titre');
      await ex.verifierTexte(eliot, /Kevin Arner\s+En attente/, 'Kevin : « En attente »');
      await ex.verifierTexte(eliot, /Sylvain Landiech\s+En attente/, 'Sylvain : « En attente »');
      await ex.verifier('« Discuter » pour chacun', async () => (await eliot.nombreDeBoutons('Discuter')) === 2);
      await ex.verifier('« Solliciter quelqu’un d’autre » (Tom reste) et « Je peux finalement venir »',
        async () => (await eliot.nombreDeBoutons('Solliciter quelqu’un d’autre')) === 1 && (await eliot.nombreDeBoutons('Je peux finalement venir')) === 1);
      await ex.verifier('pas de « Je n’ai personne d’autre » pendant l’attente', async () => (await eliot.nombreDeBoutons('Je n’ai personne d’autre')) === 0);
      for (const a of [kevin, sylvain]) {
        await a.accueil();
        await ex.verifierTexte(a, "UNE DEMANDE T'ATTEND", `${a.compte.prenom} : "Une demande t'attend"`);
        await ex.verifierTexte(a, 'Eliot a un imprévu', `${a.compte.prenom} : "Eliot a un imprévu"`);
      }
      await ex.verifier('Kevin et Sylvain notifiés (1 notification chacun)',
        () => sql(`select count(distinct profile_id) from notifications_log where profile_id in ('${COMPTES.kevin.id}', '${COMPTES.sylvain.id}')`) === '2');
    });

    await ex.etape('« Solliciter quelqu’un d’autre » : seulement les personnes pas encore sollicitées', async () => {
      await eliot.cliquer('Solliciter quelqu’un d’autre');
      await ex.verifier('seul Tom est proposé', async () => (await cases(eliot)) === 1 && (await eliot.voit('Tom Petit')));
      await eliot.cliquer('Retour');
      await ex.verifierTexte(eliot, 'C’est envoyé.', 'retour à l’attente');
    });

    await ex.etape('« Je peux finalement venir » : demandes closes, retour à la fiche', async () => {
      await A.jePeuxFinalementVenir(eliot);
      await ex.verifierTexte(eliot, 'C’est noté : tu seras là.', 'Eliot : « C’est noté : tu seras là. »');
      await ex.verifier('les deux demandes closes (personnes de nouveau simplement prévues)',
        () => demande(FICHES.kevin) === '|f' && demande(FICHES.sylvain) === '|f',
        { obtenu: () => `${demande(FICHES.kevin)} / ${demande(FICHES.sylvain)}` });
      await ex.verifier('Sylvain : « Plus besoin de répondre / Eliot pourra finalement être là pour ce Swend. »',
        () => notifs('sylvain').endsWith('Plus besoin de répondre|Eliot pourra finalement être là pour ce Swend.'),
        { obtenu: () => notifs('sylvain') });
      await sylvain.accueil();
      await ex.verifierAbsent(sylvain, "UNE DEMANDE T'ATTEND", 'Sylvain : la demande a disparu de son accueil');
      await ex.verifierTexte(sylvain, 'Eliot compte sur toi pour un Swend', 'Sylvain : de nouveau « Eliot compte sur toi »');
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Tu ne peux plus être là ?', 'Eliot : de nouveau le choix');
      await ex.verifier('les trois personnes de nouveau proposées', async () => (await cases(eliot)) === 3);
    });

    await ex.etape('Demande à Sylvain seul (confirmation à une personne), qui refuse : « Personne n’a pu… »', async () => {
      await A.cocher(eliot, 'Sylvain Landiech');
      await eliot.cliquer('Demander à Sylvain');
      await ex.verifierTexte(eliot, 'Envoyer la demande à Sylvain ?', 'confirmation : « Envoyer la demande à Sylvain ? »');
      await ex.verifierTexte(eliot, 'Si Sylvain accepte, Sylvain prendra ta place et tu ne pourras plus revenir en arrière.', 'confirmation : texte neutre');
      await eliot.cliquer('Envoyer la demande');
      await A.repondre(sylvain, false);
      await ex.verifier('refus enregistré', () => demande(FICHES.sylvain) === 'refusee|f', { obtenu: () => demande(FICHES.sylvain) });
      await ex.verifier('Eliot : « Personne n’est disponible pour l’instant / Tu peux solliciter quelqu’un d’autre. »',
        () => notifs('eliot').endsWith('Personne n’est disponible pour l’instant|Tu peux solliciter quelqu’un d’autre.'),
        { obtenu: () => notifs('eliot') });
      await A.ouvrirSwend(sylvain, /Swend d'Eliot avec David/);
      await ex.verifierTexte(sylvain, "Tu as indiqué ne pas être disponible pour prendre la place d'Eliot.", 'Sylvain : « Tu as indiqué ne pas être disponible »');
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'Personne n’a pu prendre ta place.', 'Eliot : « Personne n’a pu prendre ta place. »');
      await ex.verifierTexte(eliot, 'Tu peux encore solliciter quelqu’un d’autre.', 'Eliot : « Tu peux encore solliciter quelqu’un d’autre. »');
      await ex.verifierTexte(eliot, /Sylvain Landiech\s+Indisponible/, 'Eliot : Sylvain « Indisponible »');
      await ex.verifier('actions : Solliciter, Ajouter, Je n’ai personne d’autre, Je peux finalement venir',
        async () => (await eliot.nombreDeBoutons('Solliciter quelqu’un d’autre')) === 1
          && (await eliot.nombreDeBoutons('Ajouter une personne')) === 1
          && (await eliot.nombreDeBoutons('Je n’ai personne d’autre')) === 1
          && (await eliot.nombreDeBoutons('Je peux finalement venir')) === 1);
    });

    await ex.etape('Fiche d\'Eliot : la recherche résumée, plus aucun bouton d’annulation', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Personne n’a pu prendre ta place.', 'EN CAS D\'IMPRÉVU : « Personne n’a pu prendre ta place. »');
      await ex.verifier('fiche : pas de « Annuler le Swend »', async () => (await eliot.nombreDeBoutons('Annuler le Swend')) === 0);
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
