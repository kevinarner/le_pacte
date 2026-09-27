// Un utilisateur réel de l'app (Eliot, David, Kevin, Sylvain) : sa propre
// session navigateur isolée, connectée une fois pour tout le scénario.
// Toutes les interactions passent par les libellés d'accessibilité de l'app.
import { config, urlAutorisee, COMPTES } from './config.mjs';

const DELAI = 15000;

export class Acteur {
  constructor(nom) {
    this.nom = nom;
    this.compte = COMPTES[nom];
    this.journal = [];      // console, erreurs de page, liens ouverts
    this.liensOuverts = []; // URL passées à window.open (sms:, wa.me…)
    this.enVol = 0;         // requêtes API en cours
    this.dernierMouvement = Date.now();
  }

  noter(ligne) {
    this.journal.push(`${new Date().toISOString()} ${ligne}`);
    if (this.journal.length > 400) this.journal.shift();
  }

  async demarrer(navigateur) {
    this.contexte = await navigateur.newContext({ viewport: { width: 400, height: 860 }, locale: 'fr-FR', timezoneId: 'UTC' });
    // Garde-fou réseau : rien ne sort de la pile locale.
    await this.contexte.route('**/*', (route) => {
      const url = route.request().url();
      if (urlAutorisee(url)) return route.continue();
      this.noter(`BLOQUÉ ${url}`);
      return route.abort();
    });
    this.page = await this.contexte.newPage();
    await this.page.addInitScript(() => {
      window.open = (url) => {
        if (window.__qaEchecWhatsApp && String(url).startsWith('https://wa.me')) throw new Error('WhatsApp indisponible (simulation QA)');
        console.log('QA_OUVERT:' + url);
        return null;
      };
    });
    const estApi = (r) => r.url().startsWith(config.apiUrl);
    this.page.on('request', (r) => { if (estApi(r)) { this.enVol++; this.dernierMouvement = Date.now(); } });
    const fin = (r) => { if (estApi(r)) { this.enVol = Math.max(0, this.enVol - 1); this.dernierMouvement = Date.now(); } };
    this.page.on('requestfinished', fin);
    this.page.on('requestfailed', fin);
    this.page.on('console', (m) => {
      const t = m.text();
      if (t.startsWith('QA_OUVERT:')) { const u = t.slice(10); this.liensOuverts.push(u); this.noter(`LIEN ${u}`); }
      else this.noter(`console.${m.type()} ${t.slice(0, 300)}`);
    });
    this.page.on('pageerror', (e) => this.noter(`ERREUR PAGE ${e.message.slice(0, 300)}`));
    await this.page.goto(config.appUrl, { waitUntil: 'load' });
    await this.activerAccessibilite();
    await this.seConnecter();
  }

  // Flutter web n'expose l'arbre d'accessibilité qu'après activation.
  async activerAccessibilite() {
    await this.page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: DELAI });
    await this.page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await this.page.waitForSelector('flt-semantics-host', { state: 'attached', timeout: DELAI });
  }

  async seConnecter() {
    await this.page.getByRole('textbox').first().waitFor({ timeout: DELAI });
    await this.saisir(this.page.getByRole('textbox').nth(0), this.compte.email);
    await this.saisir(this.page.getByRole('textbox').nth(1), config.QA_MOT_DE_PASSE);
    await this.cliquer('Se connecter');
    await this.attendreTexte(`Bonjour ${this.compte.prenom}`);
    await this.accueilCharge();
  }

  async fermer() { await this.contexte?.close().catch(() => {}); }

  // --- Lecture de l'écran ---------------------------------------------------
  async texte() {
    return this.page.evaluate(() => (document.querySelector('flt-semantics-host')?.innerText || '') + '\n' +
      [...document.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label')).join('\n'));
  }
  async voit(t) {
    const x = await this.texte();
    return t instanceof RegExp ? t.test(x) : x.includes(t);
  }
  async boutons() {
    return this.page.evaluate(() => [...document.querySelectorAll('[role=button]')]
      .map((e) => (e.getAttribute('aria-label') || e.innerText || '').trim()).filter(Boolean));
  }
  // Nombre de lignes de l'écran égales à [t] (badges, libellés de cartes).
  async compterLignes(t) { return (await this.texte()).split('\n').filter((l) => l.trim() === t).length; }
  async nombreDeBoutons(nom) { return this.page.getByRole('button', { name: nom, exact: true }).count(); }

  // --- Attentes déterministes (sur l'état réel, pas des délais fixes) --------
  async attendre(condition, description, delai = DELAI) {
    const limite = Date.now() + delai;
    while (Date.now() < limite) {
      if (await condition()) return true;
      await this.page.waitForTimeout(150);
    }
    throw new Error(`${this.nom} : délai dépassé en attendant ${description}`);
  }
  async attendreTexte(t, delai = DELAI) { await this.attendre(() => this.voit(t), `« ${t} »`, delai); }
  // Plus aucune requête API en cours depuis 400 ms : l'écran est à jour.
  async attendreCalme(delai = DELAI) {
    await this.attendre(async () => this.enVol === 0 && Date.now() - this.dernierMouvement > 400, 'la fin des chargements', delai);
    await this.page.waitForTimeout(150);
  }
  async accueilCharge() {
    await this.attendreTexte(/Mes Swends\s+\d+ à venir/);
    await this.attendreCalme();
  }

  // --- Actions ----------------------------------------------------------------
  async saisir(champ, texte) {
    await champ.click();
    await this.page.waitForTimeout(150);
    await this.page.keyboard.press('Control+A');
    await this.page.keyboard.press('Backspace');
    if (texte) await this.page.keyboard.type(texte, { delay: 20 });
    // Flutter peut perdre la toute première frappe : on vérifie et on corrige.
    const valeur = await champ.inputValue().catch(() => null);
    if (valeur !== null && texte && valeur !== texte) {
      await champ.click(); await this.page.keyboard.press('Control+A'); await this.page.keyboard.press('Backspace');
      await this.page.keyboard.type(texte, { delay: 40 });
    }
  }
  async taper(libelle, texte, n = 0) {
    const champ = this.page.getByRole('textbox', { name: libelle, exact: true }).nth(n);
    await champ.waitFor({ timeout: DELAI });
    await this.saisir(champ, texte);
    await this.attendreCalme();
  }
  async cliquer(nom, { exact = true, n = 0, dernier = false } = {}) {
    const tous = this.page.getByRole('button', { name: nom, exact });
    const cible = dernier ? tous.last() : tous.nth(n);
    await cible.waitFor({ state: 'visible', timeout: DELAI });
    await cible.click();
    await this.attendreCalme();
  }
  // Élément identifié par son texte visible ou son libellé d'accessibilité.
  element(t) {
    return this.page.getByText(t, { exact: false }).or(this.page.getByLabel(t, { exact: false })).first();
  }
  async cliquerTexte(t) {
    await this.element(t).waitFor({ state: 'visible', timeout: DELAI });
    await this.element(t).click();
    await this.attendreCalme();
  }
  // Le bouton [nom] situé sur la même ligne (ou juste sous) le texte [ref].
  async cliquerPres(ref, nom) {
    await this.element(ref).waitFor({ state: 'visible', timeout: DELAI });
    const cible = await this.element(ref).boundingBox();
    const tous = this.page.getByRole('button', { name: nom, exact: true });
    await tous.first().waitFor({ state: 'visible', timeout: DELAI });
    let meilleur = null, distance = Infinity;
    for (let i = 0; i < await tous.count(); i++) {
      const b = await tous.nth(i).boundingBox();
      if (!b) continue;
      const d = Math.abs(b.y + b.height / 2 - (cible.y + cible.height / 2));
      if (d < distance) { distance = d; meilleur = tous.nth(i); }
    }
    if (!meilleur || distance > 70) throw new Error(`${this.nom} : aucun bouton « ${nom} » près de « ${ref} »`);
    await meilleur.click();
    await this.attendreCalme();
  }
  async positionY(t) { return (await this.element(t).boundingBox())?.y; }
  async estSurAccueil() {
    return (await this.voit(`Bonjour ${this.compte.prenom}`)) && (await this.page.getByRole('button', { name: 'Créer un Swend', exact: true }).count()) > 0;
  }
  // Revient à l'écran d'accueil en naviguant dans l'app (même session, pas de
  // reconnexion). Avec rafraichir, fait un aller-retour par "Mes Swends" :
  // l'accueil recharge alors ses données, comme pour un vrai utilisateur.
  async accueil({ rafraichir = true } = {}) {
    for (let i = 0; i < 12 && !(await this.estSurAccueil()); i++) {
      await this.page.keyboard.press('Escape'); // ferme une feuille ou une boîte de dialogue ouverte
      await this.page.waitForTimeout(250);
      if (await this.estSurAccueil()) break;
      const retour = this.page.getByRole('button', { name: /^(Back|Retour|Menu principal)$/ }).first();
      if (await retour.count()) await retour.click().catch(() => {});
      else await this.page.goBack();
      await this.attendreCalme();
    }
    if (!(await this.estSurAccueil())) throw new Error(`${this.nom} : impossible de revenir à l'accueil`);
    if (rafraichir) {
      await this.cliquer('Mes Swends', { exact: false });
      await this.attendreTexte('Menu principal');
      await this.cliquer('Menu principal');
      await this.attendreTexte(`Bonjour ${this.compte.prenom}`);
    }
    await this.accueilCharge();
  }
  async retour() {
    await this.page.goBack();
    await this.attendreCalme();
  }
  async capture(fichier) { await this.page.screenshot({ path: fichier, fullPage: true }).catch(() => {}); }
}
