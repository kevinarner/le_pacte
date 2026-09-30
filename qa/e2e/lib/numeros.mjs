// D-024 : numéros de téléphone reçus par l'app. On relit tout ce que l'API a
// renvoyé à un acteur (corps des réponses, messages temps réel) et on y
// cherche chaque numéro connu, sous toutes ses écritures.
import { COMPTES, CONTACTS_SANS_COMPTE } from './config.mjs';

export const NUMEROS = {
  eliot: COMPTES.eliot.tel, david: COMPTES.david.tel, kevin: COMPTES.kevin.tel, sylvain: COMPTES.sylvain.tel,
  tom: CONTACTS_SANS_COMPTE.tom.tel, leo: CONTACTS_SANS_COMPTE.leo.tel, nina: CONTACTS_SANS_COMPTE.nina.tel,
};

// "+33 6 02 03 04 05" → reconnaît 0602030405, 06 02 03 04 05, 06.02…,
// +33602030405, 0033 6 02…, +33 (0)6 02…
export function motifNumero(tel) {
  const national = tel.replace(/\D/g, '').replace(/^(0033|33|0)/, '');
  const chiffres = national.split('').join('[\\s.\\-]?');
  return new RegExp(`(?:\\+33|0033|(?<![0-9])0)[\\s.\\-]?(?:\\(0\\)[\\s.\\-]?)?${chiffres}(?![0-9])`);
}
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

// Numéros trouvés dans les réponses reçues par [acteur], hors autorisations.
// autorises : { personne: true } (partout) ou { personne: /url/ } (seulement
// dans les réponses dont l'URL correspond). Renvoie les fuites, lisibles.
export function numerosNonAutorises(acteur, autorises) {
  const fuites = new Set();
  for (const r of acteur.reponsesApi) {
    const corps = r.corps.replace(UUID, '');
    for (const [personne, tel] of Object.entries(NUMEROS)) {
      if (!motifNumero(tel).test(corps)) continue;
      const a = autorises[personne];
      if (a === true || (a instanceof RegExp && a.test(r.url))) continue;
      fuites.add(`${personne} dans ${r.methode} ${new URL(r.url).pathname}`);
    }
  }
  return [...fuites];
}

// Réponses de l'API dont l'URL correspond à [motif] (ex. /rest\/v1\/pactes/).
export const reponses = (acteur, motif, methode) =>
  acteur.reponsesApi.filter((r) => motif.test(r.url) && (!methode || r.methode === methode));
