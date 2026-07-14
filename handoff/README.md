# Handoff : Le Pacte — écrans V1

## Vue d'ensemble
"Le Pacte" est une app mobile où deux personnes fixent un rendez-vous (déjeuner/dîner) très en avance, sans jamais savoir à l'avance qui — du titulaire ou d'un remplaçant — sera réellement présent le jour J. Ce pack couvre les 6 écrans de la V1 : Connexion, Accueil (liste des pactes), Créer un pacte, Détail d'un pacte (réponse → classement → confirmation → garde-fou anti-désistement), Mes remplaçants, Profil.

## À propos des fichiers de design
Les fichiers de ce pack sont des **références de design en HTML** — des prototypes qui montrent l'apparence et le comportement visés, pas du code de production à copier tel quel. La tâche est de **recréer ces designs dans l'environnement existant du code Flutter** (`le_pacte` repo — Dart/Flutter, providers/services existants), en réutilisant les modèles de données et services déjà en place (`Pacte`, `CotePacte`, `StatutPacte`, `StatutPresence`, `Remplacant`, `Restaurant`, `AppStore`, `ClassementService`) plutôt qu'en réécrivant la logique métier.

## Fidélité
**Haute fidélité (hifi)** pour la mise en page, la hiérarchie, les couleurs et les micro-interactions (segmented control, dialog de délégation, classement réordonnable, toasts). Les couleurs exactes, polices et espacements sont documentés ci-dessous — à recréer pixel-près avec les widgets Flutter existants (Material/Cupertino de base + styles custom), pas avec le système "Organic" tel quel (c'est un habillage web ; à traduire en styles Flutter équivalents : couleurs, rayons, typo).

## Écrans

### 1. Connexion (`screens/login.png`)
- **But** : email + mot de passe, bascule connexion/inscription.
- **Layout** : colonne centrée verticalement, padding 40px/28px, gap 24px.
- **En-tête** : icône ronde 64px (fond accent clair, glyphe flèches croisées), titre "Le Pacte" (police display), sous-titre 13px centré, largeur max 260px, présentant le concept du mystère.
- **Champs** : email + mot de passe, style "field" standard (label 12px + input arrondi).
- **CTA** : bouton pleine largeur, hauteur mini 46px, libellé "Se connecter" / "Créer mon compte" selon le mode.
- **Lien bascule** : texte 13px + lien en gras sous le bouton.

### 2. Accueil (`screens/accueil.png`)
- **But** : lister les pactes de l'utilisateur courant, créer un nouveau pacte.
- **Barre du haut** : titre "Le Pacte" à gauche, bouton "Vue : {Moi|Mon ami}" à droite — bascule de perspective (simulateur 2 utilisateurs, à remplacer par le vrai compte connecté en prod).
- **Liste** : cards empilées (gap 10px), chacune : nom de l'autre partie + tag de statut (couleur selon statut — voir table Design Tokens), type de repas + date, ligne méta avec icône horloge + libellé relatif ("Dans 12 jours", "Demain"...).
- **État vide** : icône ronde + texte centré si aucun pacte.
- **CTA bas** : bouton pleine largeur "+ Nouveau pacte", fixe au-dessus de la nav.
- **Nav basse** : 3 onglets (Pactes / Remplaçants / Profil), icône + libellé, actif = couleur accent + soulignement.

### 3. Créer un pacte (`screens/creer_pacte.png`)
- **But** : proposer un cadre (type de repas, date, 3 restaurants) à l'autre personne.
- **Nav** : bouton retour + titre "Nouveau pacte".
- **Type de repas** : segmented control 2 options (Déjeuner/Dîner), pleine largeur.
- **Date** : 2 radios ("Laisser le hasard choisir" / "Je choisis la date"), le second révèle un date picker natif.
- **Restaurants** : 3 cards, chacune avec kicker "Option {n}", champ nom (obligatoire) + champ lien (optionnel).
- **Validation** : bouton "Envoyer le pacte" désactivé tant que les 3 noms ne sont pas remplis (et la date si mode manuel).

### 4. Détail d'un pacte — plusieurs états
Le détail change de contenu selon `statut` du pacte — 4 blocs conditionnels s'enchaînent dans le temps, jamais affichés simultanément (sauf l'en-tête, toujours visible) :

**En-tête (toujours visible)** : nav retour + "Pacte avec {partenaire}", card résumé (type, statut, avec/date, puis lieu+lien une fois choisi).

- **a. Bloc "Que veux-tu faire ?"** (`screens/detail_pacte_en_attente.png`) — visible uniquement par le destinataire quand statut = en attente. 3 actions : "Accepter pour moi", "Accepter et déléguer" (ouvre un dialog de sélection d'un remplaçant), "Refuser et proposer une autre date (n/2)" (désactivé après 2 refus).
- **b. Bloc classement** — visible quand statut = classement en cours. Liste réordonnable des 3 restaurants (flèches haut/bas, pas de drag actuellement — à évaluer en natif avec un vrai drag & drop), bouton "Envoyer mon classement". Une fois envoyé : message d'attente en italique. Les deux classements combinés (score = somme des rangs, le score le plus bas gagne) déterminent le restaurant retenu en secret.
- **c. Bloc garde-fou anti-désistement** (`screens/detail_pacte_confirme.png`) — visible quand statut = confirmé. Texte expliquant les relances automatiques J-7/J-3/J-1, puis 2 boutons de simulation de l'échéance finale ("rendez-vous maintenu" / "personne trouvée → annulé").
- **d. Épilogue** — card centrée, titre + texte, quand statut = maintenu ou annulé.
- **Dialog délégation** : overlay + carte modale, liste des remplaçants en boutons pleine largeur, action "Annuler".

### 5. Mes remplaçants (`screens/remplacants.png`)
- **But** : gérer sa liste de remplaçants de confiance (minimum 3 requis pour créer/recevoir un pacte).
- **Texte d'intro** 12.5px expliquant le rôle des remplaçants.
- **Avertissement** : tag si moins de 3 renseignés ("Encore N pour débloquer les pactes").
- **Liste** : card contenant chaque remplaçant en ligne — avatar photo circulaire 32px (avec initiale en placeholder), nom, bouton supprimer (croix).
- **Ajout** : champ texte + bouton icône "+".

### 6. Profil (`screens/profil.png`)
- **But** : identité de l'utilisateur courant, stats, changement de vue, déconnexion.
- **En-tête** : avatar photo circulaire 76px (placeholder "Ta photo"), nom, tag "Perspective de test".
- **Stats** : card à 2 lignes (Remplaçants enregistrés / Pactes en cours) avec compteur en tag.
- **Actions** : bouton secondaire "Changer de vue (X → Y)", bouton fantôme "Se déconnecter".

## Photos de profil
Chaque remplaçant et chaque profil a désormais un emplacement photo circulaire, cliquable/glissable dans le prototype (placeholder = initiale du nom ou "Ta photo"). En prod : upload réel (galerie/caméra), stockage (ex. Firebase Storage / S3), fallback initiale si pas de photo.

## Navigation entre pages (flow)
```
Connexion
   └─(login/signup)→ Accueil
                        ├─→ Nouveau pacte ─(envoi)→ Accueil (nouveau pacte ajouté, statut "en attente")
                        ├─→ [tap une card] → Détail du pacte
                        │       ├─ (destinataire, en attente) → Accepter / Déléguer / Refuser
                        │       │      Refuser → retour Accueil, statut "contre-proposition"
                        │       │      Accepter (direct ou via délégation) → statut "classement en cours"
                        │       ├─ (statut classement) → classer les 3 restaurants → Envoyer
                        │       │      → une fois les 2 parties ont classé → statut "confirmé"
                        │       ├─ (statut confirmé) → simulation garde-fou → "maintenu" ou "annulé"
                        │       └─ [retour] → Accueil
                        ├─→ onglet Remplaçants (nav basse)
                        ├─→ onglet Profil (nav basse)
                        │       ├─→ Changer de vue (bascule Moi/Mon ami — à remplacer par vrai multi-compte)
                        │       └─→ Se déconnecter → Connexion
                        └─→ onglet Pactes (nav basse, retour Accueil)
```
La nav basse (Pactes / Remplaçants / Profil) est présente sur les 3 écrans principaux ; Créer et Détail s'ouvrent par-dessus avec un bouton retour dédié (pas de nav basse).

## État & logique métier (déjà dans le repo `le_pacte`, à réutiliser)
- Modèles : `Pacte`, `CotePacte` (titulaire + remplaçants + statutPresence), `StatutPacte` (enAttenteReponse, refuseContreProposition, accepteEnAttenteClassement, confirme, maintenu, annule), `StatutPresence`, `Remplacant`, `Restaurant`, `TypeRepas`.
- Services : `AppStore` (état global des pactes/remplaçants), `ClassementService` (calcul du restaurant élu — somme des rangs, le plus bas gagne, tie-break sur préférence du destinataire).
- Règles à conserver : minimum 3 remplaçants pour créer/recevoir un pacte ; max 2 refus avant blocage ; le restaurant élu et le remplaçant sollicité ne sont jamais révélés à l'avance (mystère jusqu'au jour J).

## Design tokens (visuels du prototype — à traduire en styles Flutter)
- **Fond** : crème chaud `#f5ead8` (ambiance globale plus foncée en dehors du cadre `#e7ddcb`).
- **Texte** : `#201e1d`.
- **Accent principal (terracotta)** : base `#c67139`, utilisé pour CTA primaires, tag "Confirmé/Maintenu", icônes clés. Rampe 100→900 (clairs pour fonds tintés, foncés pour texte sur fond tinté).
- **Accent secondaire (sauge)** : base `#7a8a5e`, utilisé pour le bloc classement, tag "compteurs", avatars remplaçants.
- **Typo** : titres en police display arrondie (Caprasimo-like), corps en Figtree. Tailles : titres d'écran ~16-18px, titres de card ~15-16px, corps ~13-14.5px, méta/labels ~12-13px.
- **Rayons** : cards/inputs `16px` (`--radius-lg`), boutons et avatars en pilule/cercle (`999px`).
- **Ombres** : `elev-sm` sur les cards importantes (résumé de pacte, liste accueil, épilogue).
- **Tags de statut** :
  - En attente de réponse → neutre (gris clair)
  - Contre-proposition envoyée → outline
  - Classement en cours → accent secondaire (sauge clair)
  - Confirmé / Maintenu → accent principal (terracotta)
  - Annulé → neutre

## Assets
- `screens/*.png` — captures des 6 écrans (+ 2 variantes d'état du détail) du prototype HTML, à utiliser comme référence visuelle pixel-à-pixel.
- Aucune image bitmap custom (icônes en SVG inline trait 2.75, style Lucide) ; les photos de profil sont des emplacements vides à remplir par l'utilisateur (pas d'asset fourni).

## Fichiers
Le prototype complet (markup + logique d'état + tous les écrans) est dans `Le Pacte.dc.html` à la racine du projet de design. C'est un fichier auto-descriptif : chaque écran y est un bloc conditionnel commenté (`<!-- ============ ACCUEIL ============ -->` etc.), et la logique d'état (statuts, calcul du restaurant élu, règles de refus) est dans la classe `Component` en bas du fichier — à lire comme référence de comportement, pas à copier tel quel (c'est du HTML/JS, pas du Dart).
