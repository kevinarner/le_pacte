// MESSAGES / WHATSAPP — "Inviter et demander" pour Tom (sans compte) :
// demande enregistrée, liens au format E.164, texte, repli WhatsApp → Messages.
import * as A from '../lib/actions.mjs';
import { demande, FICHES } from '../lib/donnees.mjs';
import { CONTACTS_SANS_COMPTE as C } from '../lib/config.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

const texteDe = (lien) => decodeURIComponent(lien.split(/[?&](?:body|text)=/)[1] || '');

export default {
  nom: 'inviter_et_demander',
  titre: 'Inviter et demander (Tom) : liens Messages / WhatsApp, repli',
  suites: ['full'],
  fixture: 'scelle',
  async executer(ex) {
    const eliot = await ex.eliot();
    ex.memo.david = await photoDavid(ex);
    const dernierLien = () => eliot.liensOuverts.at(-1) || '';

    await ex.etape('Inviter et demander → Messages', async () => {
      await A.ouvrirImprevu(eliot);
      await A.inviterEtDemander(eliot, 'Tom Petit');
      await ex.verifier('demande à Tom enregistrée avant l\'envoi du message', () => demande(FICHES.tom) === 'envoyee|f', { obtenu: () => demande(FICHES.tom) });
      await ex.verifierTexte(eliot, 'Le message est prérempli', 'choix Messages / WhatsApp affiché');
      await eliot.cliquer('Messages');
      await ex.verifier('lien Messages vers le numéro E.164 de Tom',
        () => dernierLien().startsWith(`sms:${C.tom.e164}?body=`), { obtenu: dernierLien });
      const texte = texteDe(dernierLien());
      await ex.verifier('texte : demande de prendre la place', () => texte.startsWith('Hello Tom') && texte.includes('Est-ce que tu pourrais prendre ma place ?'), { obtenu: () => texte });
      await ex.verifier('texte : phrase "crée ton compte avec ce numéro de téléphone"',
        () => texte.includes('Pour retrouver cette demande dans Swend, crée ton compte avec ce numéro de téléphone.'), { obtenu: () => texte });
      await ex.verifier('texte : restaurant et autre participant', () => texte.includes('Au père Lapin') && texte.includes('avec David'), { obtenu: () => texte });
      await ex.verifierTexte(eliot, /Tom Petit\s+En attente/, 'Tom : "En attente"');
    });

    await ex.etape('"Envoyer le message" → WhatsApp', async () => {
      await eliot.cliquer('Envoyer le message');
      await eliot.cliquer('WhatsApp');
      await ex.verifier('lien wa.me sans "+" (33711223344)',
        () => dernierLien().startsWith(`https://wa.me/${C.tom.e164.slice(1)}?text=`), { obtenu: dernierLien });
      await ex.verifier('même texte quel que soit le canal',
        () => texteDe(dernierLien()) === texteDe(eliot.liensOuverts.at(-2)), { obtenu: () => texteDe(dernierLien()) });
    });

    await ex.etape('WhatsApp indisponible → "Utiliser Messages"', async () => {
      await eliot.page.evaluate(() => { window.__qaEchecWhatsApp = true; });
      const avant = eliot.liensOuverts.length;
      await eliot.cliquer('Envoyer le message');
      await eliot.cliquer('WhatsApp');
      await ex.verifierTexte(eliot, "WhatsApp n'a pas pu s'ouvrir.", 'message "WhatsApp n\'a pas pu s\'ouvrir."');
      await ex.verifier('aucun lien ouvert pendant l\'échec', () => eliot.liensOuverts.length === avant);
      await eliot.cliquer('Utiliser Messages');
      await ex.verifier('repli : lien Messages ouvert', () => dernierLien().startsWith(`sms:${C.tom.e164}?body=`), { obtenu: dernierLien });
      await eliot.page.evaluate(() => { window.__qaEchecWhatsApp = false; });
    });

    await ex.etape('Modifier ma liste : invitation de personne de confiance (sans demande)', async () => {
      await eliot.accueil({ rafraichir: false });
      await A.ouvrirModifierMaListe(eliot);
      await eliot.cliquer("Envoyer l'invitation");
      await eliot.cliquer('Messages');
      const texte = texteDe(dernierLien());
      await ex.verifier('invitation : bon numéro', () => dernierLien().startsWith(`sms:${C.tom.e164}?body=`), { obtenu: dernierLien });
      await ex.verifier('invitation : "j\'ai proposé un Swend à David"', () => texte.includes("j'ai proposé un Swend à David"), { obtenu: () => texte });
      await ex.verifier('invitation : ne parle pas d\'une demande en cours', () => !texte.includes('imprévu. Est-ce'), { obtenu: () => texte });
    });

    await ex.etape('David ne voit rien', async () => {
      await verifierDavidNeVoitRien(ex, ex.memo.david);
    });
  },
};
