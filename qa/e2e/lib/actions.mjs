// Actions métier réutilisables, exprimées comme un utilisateur les fait.
// Chaque action part de l'écran d'accueil (données fraîches) sauf mention.

const deNom = (p) => (/^[aeiouyhàâäéèêëîïôöùûü]/i.test(p) ? `d'${p}` : `de ${p}`);
export { deNom };

// --- Navigation --------------------------------------------------------------
export async function ouvrirMesSwends(a) {
  await a.accueil({ rafraichir: false });
  await a.cliquer('Mes Swends', { exact: false });
  await a.attendreTexte('Menu principal');
}
// motif : RegExp du libellé de la carte ("Swend avec David", "Swend d'Eliot avec David").
export async function ouvrirSwend(a, motif) {
  await ouvrirMesSwends(a);
  await a.page.getByRole('button', { name: motif }).first().waitFor({ timeout: 15000 });
  await a.page.getByRole('button', { name: motif }).first().click();
  await a.attendreCalme();
}
export async function ouvrirImprevu(a, motif = /Swend avec/) {
  await ouvrirSwend(a, motif);
  await a.cliquer('Un imprévu ?');
  await a.attendreTexte(/Qui peut prendre votre place|Personne n'est encore prévu|Aucune des personnes prévues|prendra votre place\./);
}
export async function ouvrirModifierMaListe(a, motif = /Swend avec/) {
  await ouvrirSwend(a, motif);
  await a.cliquer(/^(Modifier ma liste|Ajouter des personnes|Voir les personnes prévues)$/, { exact: false });
  await a.attendreTexte('Modifier ma liste');
}

// --- Création et scellement -------------------------------------------------
// personnes : [{ prenom, nom, tel }] (au moins 2 : minimum de l'étape 3).
export async function creerSwend(a, { prenom, nom, tel, personnes }) {
  await a.accueil({ rafraichir: false });
  await a.cliquer('Créer un Swend');
  await a.taper('Prénom', prenom);
  await a.taper('Nom', nom);
  await a.taper('Numéro de mobile', tel);
  await a.cliquer('Suivant');
  await a.cliquer('Ajouter une date');
  await a.cliquer('OK');
  await a.cliquer('Suivant');
  await remplirPersonnes(a, personnes);
  await a.cliquer('Envoyer le Swend');
  await a.attendreTexte(`Bonjour ${a.compte.prenom}`);
  await a.accueilCharge();
}
export async function remplirPersonnes(a, personnes, depart = 0) {
  for (let i = 0; i < personnes.length; i++) {
    const n = depart + i;
    if ((await a.page.getByRole('textbox', { name: 'Prénom', exact: true }).count()) <= n) await a.cliquer('Ajouter une personne');
    await a.taper('Prénom', personnes[i].prenom, n);
    await a.taper('Nom', personnes[i].nom, n);
    await a.taper('Numéro de mobile', personnes[i].tel, n);
    await statutAffiche(a, personnes[i].prenom);
  }
}
// La ligne "[Prénom] est déjà sur Swend / n'a pas encore Swend" apparaît
// après la saisie du numéro et décale la mise en page : on l'attend.
export async function statutAffiche(a, prenom) {
  await a.attendre(() => a.voit(new RegExp(`${prenom} (est déjà sur Swend|n'a pas encore Swend)`)), 'la ligne de statut Swend', 5000)
    .catch(() => {});
  await a.attendreCalme();
}
// Le destinataire choisit la date proposée puis accepte avec ses personnes.
export async function choisirPremiereDate(a) {
  await a.page.getByRole('button', { name: /\d{4} à \d{1,2}h\d{2}/ }).first().waitFor({ timeout: 15000 });
  await a.page.getByRole('button', { name: /\d{4} à \d{1,2}h\d{2}/ }).first().click();
  await a.attendreTexte('Accepter le Swend');
}
export async function accepterSwend(a, { avec = /Swend avec/, personnes }) {
  await ouvrirSwend(a, avec);
  await choisirPremiereDate(a);
  await remplirPersonnes(a, personnes);
  await a.cliquer('Accepter le Swend');
  await a.attendreTexte('Scellé');
}

// --- Personnes de confiance -------------------------------------------------
export async function ajouterPersonnes(a, personnes, motif = /Swend avec/) {
  await ouvrirModifierMaListe(a, motif);
  const deja = await a.page.getByRole('textbox', { name: 'Prénom', exact: true }).count();
  await remplirPersonnes(a, personnes, deja);
  await a.cliquer('Enregistrer');
}
export async function retirerPersonne(a, nomComplet, motif = /Swend avec/) {
  await ouvrirModifierMaListe(a, motif);
  await a.cliquerPres(nomComplet, 'Retirer');
  await a.cliquer('Retirer', { dernier: true }); // confirmation
}

// --- Un imprévu ? (titulaire) ---------------------------------------------
export async function demander(a, nomComplet) {
  await a.cliquerPres(nomComplet, 'Lui demander');
  await a.cliquer('Envoyer la demande');
}
export async function annulerDemande(a, nomComplet) {
  await a.cliquerPres(nomComplet, 'Annuler la demande');
}
// Ouvre le choix Messages / WhatsApp (la demande est déjà partie).
export async function inviterEtDemander(a, nomComplet) {
  await a.cliquerPres(nomComplet, 'Inviter et demander');
  await a.cliquer('Inviter et demander', { dernier: true });
  await a.attendreTexte('Envoyer la demande');
}

// --- Personne de confiance (tiers) -----------------------------------------
// Répond depuis la demande affichée sur son accueil.
export async function repondre(a, accepte) {
  await a.accueil();
  await a.cliquer('Répondre à la demande');
  await a.cliquer('Voir la demande et répondre');
  await a.attendreTexte('Accepter');
  await validerReponse(a, accepte);
}
// Dans la conversation, bandeau de demande visible.
export async function validerReponse(a, accepte) {
  if (accepte) {
    await a.cliquer('Accepter');
    await a.cliquer('Accepter', { dernier: true }); // confirmation
  } else {
    await a.cliquer('Refuser');
  }
}
// Répond depuis la fiche d'un Swend précis (utile quand plusieurs demandes attendent).
export async function repondreDepuisSwend(a, titulaire, autre, accepte) {
  await ouvrirSwend(a, new RegExp(`Swend ${deNom(titulaire)} avec ${autre}`));
  await a.cliquer('Voir la demande et répondre');
  await a.attendreTexte('Accepter');
  await validerReponse(a, accepte);
}
export async function seDesister(a, titulaire = 'Eliot', autre = 'David') {
  await ouvrirSwend(a, new RegExp(`Swend ${deNom(titulaire)} avec ${autre}`));
  await a.cliquer('Je ne peux finalement plus venir');
  await a.cliquer('Je ne peux plus venir');
}

// --- Conversations -----------------------------------------------------------
export async function envoyerMessage(a, texte) {
  const champ = a.page.getByRole('textbox', { name: 'Écrire un message…' });
  await champ.waitFor({ timeout: 15000 });
  await a.saisir(champ, texte); // vérifie la saisie (première frappe parfois perdue)
  await a.page.keyboard.press('Enter');
  await a.attendreCalme();
  await a.attendreTexte(texte); // affiché dans la conversation (flux en direct)
}
// Titulaire : depuis la fiche, via "Discuter" puis le nom.
export async function ouvrirConversationTitulaire(a, nomComplet, motif = /Swend avec/) {
  await ouvrirSwend(a, motif);
  await a.cliquer('Discuter');
  await a.cliquerTexte(nomComplet);
  await a.attendreTexte('Écrire un message…');
}
// Personne de confiance : depuis la fiche du Swend, "Écrire à <titulaire>".
export async function ouvrirConversationTiers(a, titulaire = 'Eliot', autre = 'David') {
  await ouvrirSwend(a, new RegExp(`Swend ${deNom(titulaire)} avec ${autre}`));
  await a.cliquer(`Écrire à ${titulaire}`, { exact: false });
  await a.attendreTexte('Écrire un message…');
}
// Depuis la box "X vous a écrit" de l'accueil.
export async function ouvrirConversationDepuisBox(a, nomComplet) {
  await a.accueil();
  await a.cliquerTexte(`${nomComplet} vous a écrit`);
  await a.attendreTexte('Écrire un message…');
}
