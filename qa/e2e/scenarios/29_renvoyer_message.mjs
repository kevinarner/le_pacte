// D-027 — RÉACTIVATION D'UNE PERSONNE SANS COMPTE : Tom (sans compte) était
// en attente quand Kevin a accepté ; Kevin se désiste, la demande de Tom
// redevient active mais jamais en silence : Eliot voit « Renvoyer le
// message à Tom » (fiche du Swend et « Un imprévu ? »), avec le message
// d'urgence actualisé, jusqu'à ce qu'il l'ait renvoyé.
import * as A from '../lib/actions.mjs';
import { sql, demande, FICHES } from '../lib/donnees.mjs';
import { COMPTES, CONTACTS_SANS_COMPTE as C } from '../lib/config.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const aRenvoyer = () => sql(`select message_a_renvoyer from remplacants where id = '${FICHES.tom}'`);
const texteDe = (lien) => decodeURIComponent(lien.split(/[?&](?:body|text)=/)[1] || '');
const derniereDe = (nom) => sql(`select titre || '|' || corps from notifications_log where profile_id = '${COMPTES[nom].id}' order by id desc limit 1`);

export default {
  nom: 'renvoyer_message',
  titre: 'Tom (sans compte) réactivé après un désistement : « Renvoyer le message à Tom »',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    const kevin = await ex.kevin();
    const sylvain = await ex.sylvain();
    ex.memo.david = await photoDavid(ex);
    const dernierLien = () => eliot.liensOuverts.at(-1) || '';

    await ex.etape('Eliot sollicite Tom (message envoyé) et Kevin ; Kevin accepte', async () => {
      await A.ouvrirImprevu(eliot);
      await A.inviterEtDemander(eliot, 'Tom Petit');
      await eliot.cliquer('Messages');
      await A.demander(eliot, 'Kevin Arner');
      await A.repondre(kevin, true);
      await ex.verifier('Tom clôturé, sans message à renvoyer',
        () => demande(FICHES.tom) === 'cloturee|f' && aRenvoyer() === 'f', { obtenu: () => `${demande(FICHES.tom)} ${aRenvoyer()}` });
    });

    await ex.etape('Kevin se désiste : la demande de Tom est réactivée, message à renvoyer', async () => {
      await A.seDesister(kevin);
      await ex.verifier('Tom de nouveau "envoyee", message à renvoyer',
        () => demande(FICHES.tom) === 'envoyee|f' && aRenvoyer() === 't', { obtenu: () => `${demande(FICHES.tom)} ${aRenvoyer()}` });
      await ex.verifier('Eliot : push "Kevin ne peut finalement plus venir / Les personnes qui n’avaient pas encore répondu…"',
        () => derniereDe('eliot') === 'Kevin ne peut finalement plus venir|Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.',
        { obtenu: () => derniereDe('eliot') });
    });

    await ex.etape('Fiche du Swend : « Renvoyer le message à Tom » → Messages', async () => {
      await A.ouvrirSwend(eliot, /Swend avec David/);
      await ex.verifierTexte(eliot, 'Renvoyer le message à Tom', 'Eliot : action "Renvoyer le message à Tom" sur la fiche');
      await eliot.cliquer('Renvoyer le message à Tom');
      await ex.verifierTexte(eliot, 'Le message est prérempli', 'choix Messages / WhatsApp affiché');
      await eliot.cliquer('Messages');
      await ex.verifier('lien Messages vers le numéro E.164 de Tom',
        () => dernierLien().startsWith(`sms:${C.tom.e164}?body=`), { obtenu: dernierLien });
      const texte = texteDe(dernierLien());
      await ex.verifier('message d\'urgence actualisé : demande, restaurant, autre participant',
        () => texte.startsWith('Hello Tom') && texte.includes('Est-ce que tu pourrais prendre ma place ?')
          && texte.includes('Au père Lapin') && texte.includes('avec David'), { obtenu: () => texte });
      await ex.verifier('message marqué renvoyé, demande toujours en attente',
        () => aRenvoyer() === 'f' && demande(FICHES.tom) === 'envoyee|f', { obtenu: () => `${demande(FICHES.tom)} ${aRenvoyer()}` });
      await ex.verifierAbsent(eliot, 'Renvoyer le message à Tom', 'Eliot : l\'action disparaît de la fiche');
    });

    await ex.etape('Nouveau cycle : Sylvain accepte puis se désiste', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Sylvain Landiech');
      await A.repondre(sylvain, true);
      await A.seDesister(sylvain);
      await ex.verifier('Tom de nouveau à relancer',
        () => demande(FICHES.tom) === 'envoyee|f' && aRenvoyer() === 't', { obtenu: () => `${demande(FICHES.tom)} ${aRenvoyer()}` });
    });

    await ex.etape('« Un imprévu ? » : l\'action reste tant que le message n\'est pas renvoyé', async () => {
      await A.ouvrirImprevu(eliot);
      await ex.verifierTexte(eliot, 'La demande attend de nouveau sa réponse.', 'Un imprévu ? : explication');
      await ex.verifierTexte(eliot, 'Renvoyer le message à Tom', 'Un imprévu ? : "Renvoyer le message à Tom"');
      await ex.verifier('pas de lien "Envoyer le message" en double', async () => (await eliot.nombreDeBoutons('Envoyer le message')) === 0);
      await eliot.cliquer('Renvoyer le message à Tom');
      await eliot.cliquer('WhatsApp');
      await ex.verifier('lien wa.me vers Tom',
        () => dernierLien().startsWith(`https://wa.me/${C.tom.e164.slice(1)}?text=`), { obtenu: dernierLien });
      await ex.verifier('message marqué renvoyé', () => aRenvoyer() === 'f', { obtenu: aRenvoyer });
      await ex.verifierAbsent(eliot, 'Renvoyer le message à Tom', 'Un imprévu ? : l\'action disparaît');
      await ex.verifierTexte(eliot, /Tom Petit\s+En attente/, 'Tom : "En attente"');
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
