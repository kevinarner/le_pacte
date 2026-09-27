# Swend — ce que fait l'application (à lire avant toute intervention)

> Document de référence **produit** destiné à un assistant (Claude) ou à un
> nouveau collaborateur. Il décrit ce que fait Swend, ses règles et son
> vocabulaire, tel que c'est implémenté aujourd'hui (27/09/2026).
> Détails techniques complets : `ARCHITECTURE.md`. Banc de tests : `qa/README.md`.
> Règles produit attendues (source de vérité) : `PRODUCT_RULES.md` ; historique
> des arbitrages : `DECISIONS.md`.
>
> Lot D-008 / D-015 (indisponibilité spontanée, notifications des actions
> directes) : en production depuis le 27/09 (migration
> `20260927010000_disponibilite_spontanee_et_notifications.sql` exécutée).
>
> Lot D-019 / D-011 (personnes de confiance actives après scellage, limite
> de négociation garantie par la base) : en production depuis le 27/09
> (migration `20260927020000_scellage_et_negociation.sql` exécutée).

---

## 1. L'idée en une phrase

Deux personnes fixent un déjeuner ou un dîner à l'avance ; chacune peut, en cas
d'imprévu, se faire remplacer par une **personne de confiance** qu'elle a
choisie — **sans que l'autre le sache**. Le jour J, on ne sait donc jamais
vraiment qui sera en face : c'est le « mystère » de Swend.

Swend a porté d'autres noms : « Le Pacte », puis « Pakt ». Le code et la base
utilisent encore `pacte` / `pactes` : **un pacte = un Swend**.

- App web (Flutter) : https://kevinarner.github.io/le_pacte/
- Backend : Supabase (Postgres + RLS + fonctions SQL), notifications push FCM.
- Un seul restaurant pour l'instant : « Au père Lapin ».

---

## 2. Vocabulaire (celui de l'interface)

| Terme | Sens |
|---|---|
| **Swend** | Un repas prévu entre deux personnes (table `pactes`). |
| **Initiateur** | Celui qui crée le Swend (ex. Eliot). |
| **Destinataire** | Celui à qui il est proposé (ex. David). |
| **Titulaire** | Initiateur ou destinataire : un des deux participants « officiels ». |
| **Personne de confiance** | Quelqu'un qu'un titulaire a prévu pour prendre sa place si besoin (table `remplacants`, anciennement « remplaçant »). Propre à un Swend et à **un côté**. |
| **Tiers** | Le rôle d'une personne de confiance quand elle ouvre l'app. |
| **Scellé** | Swend confirmé (date et restaurant fixés), statut `confirme`. |
| **« Un imprévu ? »** | Le parcours par lequel un titulaire demande à ses personnes de confiance de prendre sa place. |
| **Demande** | Une sollicitation « Un imprévu ? » envoyée à une personne précise. |
| **Désistement** | Une personne qui avait accepté ne peut finalement plus venir. |

Ton : le titulaire est **vouvoyé** sur ses écrans de gestion (« Un imprévu ? »,
fiche du Swend) ; les personnes de confiance sont **tutoyées**.

---

## 3. La règle d'or : la confidentialité

**L'autre participant ne doit jamais rien savoir** des démarches de remplacement
de son vis-à-vis. Si Eliot se fait remplacer par Kevin, David ne voit :

- aucune notification ;
- aucun changement de nom, de statut ou d'écran ;
- aucune donnée via l'API : la base (RLS) l'en empêche, pas seulement l'interface.

Conséquences concrètes :

- Chaque titulaire ne voit **que ses propres** personnes de confiance.
- Une personne de confiance ne voit **que sa propre fiche**. Elle ne voit ni
  les autres personnes prévues, ni la liste de l'autre côté.
- Il n'existe **aucun fil de discussion** entre une personne de confiance et
  l'autre participant.
- Seule exception : si **les deux** titulaires se font remplacer, le Swend est
  annulé et chacun apprend que « vous avez chacun dû faire appel à quelqu'un ».
  Il n'apprend **jamais qui**.
- Cas limite accepté : si une même personne est prévue des deux côtés et prend
  la place d'un côté, elle apparaît « Indisponible » de l'autre, sans raison ni
  notification.

Toute modification doit préserver cette règle. Le banc QA la vérifie dans
chaque scénario de remplacement (écran de David, lecture API sous son compte,
notifications).

---

## 4. Personnages de référence (utilisés partout, y compris dans les tests)

- **Eliot** : crée un Swend avec **David**.
- **Kevin** et **Sylvain** : personnes de confiance d'Eliot, qui ont un compte Swend.
- **Tom** : personne de confiance d'Eliot, **sans compte**.
- **Léo** et **Nina** : personnes de confiance de David, sans compte.

---

## 5. Le parcours complet

### 5.1 Création (Eliot) : 3 étapes

1. **« Avec qui ? »** : prénom, nom, numéro de mobile de David (ou choix dans
   les contacts). On voit tout de suite « David est déjà sur Swend », ou
   « David n'a pas encore Swend » avec un bouton « Envoyer l'invitation ».
2. **« Quand et où ? »** : déjeuner ou dîner, une ou plusieurs dates proposées,
   au restaurant.
3. **« En cas d'imprévu »** : au moins 2 personnes de confiance (5 au plus en
   une seule saisie ; on peut en ajouter d'autres plus tard, sans plafond global).

Puis « Envoyer le Swend ». Si David a déjà un compte, il le reçoit
(notification). Sinon, le Swend l'attend : il lui sera rattaché
automatiquement dès qu'il créera son compte avec ce numéro, quel que soit le
format saisi.

Les personnes de confiance choisies à l'étape 3 ne sont **pas encore
actives** : tant que le Swend n'est pas scellé, Kevin n'en sait rien. Il n'a
ni carte « On compte sur toi », ni accès au Swend, ni conversation, ni
notification. La base le garantit. Il devient actif au scellage (voir 5.6).
Si David refuse ou si la négociation échoue, Kevin ne voit jamais ce Swend.
Seule exception : un message Messages / WhatsApp qu'Eliot choisit lui-même
d'envoyer (« Envoyer l'invitation »).

### 5.2 Réponse (David)

- David choisit une des dates proposées, ou fait une contre-proposition.
  Après la proposition initiale, il y a **au plus 2 contre-propositions au
  total**, les deux confondus (A par Eliot, B par David = n°1, C par Eliot =
  n°2). Ensuite il ne reste qu'à accepter une date proposée ou à annuler le
  Swend (« Dernière proposition : si aucune de ces dates ne convient, le Swend
  sera annulé. »). La base refuse toute contre-proposition de plus. Pour
  renégocier, il faut créer un nouveau Swend.
- Pour **accepter**, il renseigne à son tour ses propres personnes de
  confiance (au moins 2), puis « Accepter le Swend ». Le Swend est alors
  **Scellé**.
- Il peut aussi **refuser** (« Refuser le Swend »). Le Swend est alors annulé.

Statuts affichés dans « Mes Swends » : « À vous de répondre », « En attente de
David », « Date à confirmer », « Scellé », « Annulé ✗ ».

### 5.3 Swend scellé : fiche du titulaire

La fiche montre la date, le restaurant et l'autre participant, puis le bloc
**« EN CAS D'IMPRÉVU »** :

- la liste des prénoms des personnes **encore disponibles**, celles qui ont un
  compte d'abord (ex. « Kevin, Sylvain, Tom ») ;
- deux boutons : **« Modifier ma liste »** (préparer) et **« Discuter »**
  (écrire à l'une des personnes de la liste qui a un compte) ;
- sous le bloc, un bouton **« Un imprévu ? »** (demander).

Il y a trois intentions bien séparées : **préparer**, **discuter**,
**demander**. Aucune demande ne part depuis « Modifier ma liste ».

### 5.4 « Modifier ma liste » (préparation)

- Voir chaque personne avec son statut Swend (« est déjà sur Swend » /
  « n'a pas encore Swend » + « Envoyer l'invitation »).
- Voir son état : « En attente », « Indisponible » (refus, désistement,
  demande close, ou indisponibilité signalée par la personne elle-même),
  « Prend ta place ✓ ».
- Ajouter des personnes (« Enregistrer »).
- Retirer une personne. Ce n'est pas possible si une demande est en cours ou
  si la personne a accepté.

### 5.5 « Un imprévu ? » (demander à quelqu'un de prendre sa place)

Écran « Qui peut prendre votre place ? ». Pour chaque personne :

- **« Lui demander »** si elle a un compte : confirmation, puis la demande part
  et elle reçoit une notification.
- **« Inviter et demander »** si elle n'a pas de compte : la demande est
  enregistrée, puis s'ouvre le choix **Messages** (SMS) ou **WhatsApp** avec
  un message d'urgence prérempli. Ce message contient la date, l'heure, avec
  qui, le restaurant, la règle du mystère et « Pour retrouver cette demande
  dans Swend, crée ton compte avec ce numéro de téléphone. » Si WhatsApp ne
  s'ouvre pas, l'app propose « Utiliser Messages ».
- **« En attente »** une fois demandé, avec « Annuler la demande » et « Écrire
  à … » (ou « Envoyer le message » pour une personne sans compte).
- **« Indisponible »** si la personne a refusé, s'est désistée, si la
  demande a été close, ou si elle a indiqué d'elle-même qu'elle ne serait pas
  disponible (voir 5.6). Elle ne peut alors pas être sollicitée.

Règles :

- On peut demander à **plusieurs personnes en même temps**, sans ordre de
  priorité.
- **La première qui accepte prend la place.** C'est garanti par la base, même
  en cas d'acceptations simultanées. Les autres demandes en attente sont
  **closes** automatiquement.
- **Accepter est définitif** : le titulaire ne peut plus annuler ni reprendre
  sa place. Seul un désistement de la personne rouvre la recherche.
- **« Ajouter quelqu'un »** : ajoute une personne et lui envoie directement la
  demande, en une seule action. Il n'y a pas de plafond.
- Si personne n'est disponible, l'action principale est « Ajouter quelqu'un ».
  « Annuler le Swend » reste possible en dernier recours.
- Une fois quelqu'un d'accord : « Kevin prendra votre place. Votre Swend reste
  scellé. » Le titulaire garde « Écrire à Kevin » et « Discuter ».

### 5.6 Côté personne de confiance (Kevin)

Tout ce qui suit n'existe qu'à partir du scellage du Swend.

Sur son accueil :

- **« ON COMPTE SUR TOI »** : « Eliot compte sur toi pour un Swend » + « Voir
  le Swend ». Ce n'est **pas** un Swend « à venir » pour lui.
- **« UNE DEMANDE T'ATTEND »** (en tête) : « Eliot a un imprévu » +
  « Répondre à la demande ».
- Après acceptation : « Tu prends la place d'Eliot ». Le Swend devient alors
  **son** Swend à venir (« Ton prochain Swend », compteur « 1 à venir »).

**Indisponibilité spontanée** (tant qu'il est simplement prévu, sans demande
en cours) : sur la carte « Eliot compte sur toi » et sur la fiche du Swend,
une action secondaire **« Je ne serai pas disponible »**, sans formulaire ni
justification.

- Kevin devient « Indisponible » pour ce Swend. Il reste dans « On compte sur
  toi » (« Tu as indiqué que tu ne seras pas disponible. Eliot le sait. »).
- L'action devient **« Je suis finalement disponible »**, qui annule tout.
- Eliot est prévenu (box sur l'accueil + push). Kevin reste listé dans
  « Modifier ma liste » (« Indisponible »), mais n'est plus proposé dans « En
  cas d'imprévu » ni sollicitable dans « Un imprévu ? ».
- C'est réversible, contrairement au refus d'une vraie demande et au
  désistement après acceptation, qui restent définitifs pour ce Swend.
  L'action n'existe pas pendant une demande en cours (il faut y répondre),
  ni après avoir accepté (c'est alors le désistement).

Sur la fiche du Swend (vue « tiers », minimale) :

- toujours la date, l'heure, le restaurant et **avec qui** ;
- selon l'état :
  - « Eliot peut faire appel à toi en cas d'imprévu. Tu n'as rien à faire pour
    le moment. » + « Je ne serai pas disponible » ;
  - « Tu as indiqué que tu ne seras pas disponible pour ce Swend. Eliot le
    sait. » + « Je suis finalement disponible » ;
  - « Eliot a un imprévu » + « Voir la demande et répondre » ;
  - « Tu as indiqué ne pas être disponible… » ;
  - « C'est bon, quelqu'un a pu prendre la place d'Eliot. » (on ne dit jamais
    qui) ;
  - « Tu prends la place d'Eliot » + **« Je ne peux finalement plus venir »**
    (le désistement, uniquement ici) ;
- toujours « Écrire à Eliot » ;
- aucune action de gestion, et aucun contact avec David.

**Accepter / Refuser** se fait uniquement dans la conversation avec Eliot, où
tout le contexte est affiché (« David ne saura pas que tu prends la place
d'Eliot »). Accepter demande une confirmation.

### 5.7 Désistement

Kevin, qui avait accepté, clique « Je ne peux finalement plus venir » :

- Kevin ne prend plus la place, et le Swend **disparaît de ses Swends**.
- Les personnes dont la demande avait été close **redeviennent disponibles**,
  mais **aucune demande n'est renvoyée automatiquement**.
- Celles qui avaient refusé restent indisponibles.
- Eliot retrouve son bloc « En cas d'imprévu » et peut redemander.
- David ne voit rien.

### 5.8 Double remplacement

Si Eliot **et** David ont chacun quelqu'un qui prend leur place, le Swend est
**annulé automatiquement** (`annuleDoubleAbsence`) : « Swend annulé — Vous avez
chacun dû faire appel à quelqu'un pour vous remplacer… ». Faire dîner ensemble
deux remplaçants qui ne se connaissent pas est volontairement hors V1.

### 5.9 Même personne des deux côtés

Kevin peut être prévu à la fois par Eliot et par David :

- L'app ne lui montre **qu'une carte** pour ce Swend. C'est celle de sa fiche
  la plus active : d'abord celle où il prend la place, puis une demande en
  attente.
- Dès qu'il accepte d'un côté, il devient « Indisponible » de l'autre, sans
  notification.
- Un titulaire ne peut pas lui envoyer de demande tant qu'il a pris la place
  de l'autre côté.
- Il ne peut jamais prendre les deux places.

---

## 6. Messagerie

- **Un fil privé par (Swend, personne de confiance)** : entre le titulaire et
  cette personne, dès qu'elle a un compte. Il est utilisable à tout moment,
  même sans demande en cours.
- Messages en direct, dans l'ordre chronologique.
- **Événements système dans le fil**, horodatés, rédigés selon qui lit. Par
  exemple :
  - titulaire : « Tu as demandé à Kevin de prendre ta place. » ;
  - Kevin : « Eliot t'a demandé de prendre sa place. ».

  Il y en a huit : demande envoyée, annulée, refusée, acceptée, désistement,
  demande close (« La demande n'est plus d'actualité. »), indisponibilité
  signalée, retour disponible. Ils sont enregistrés en base et persistent.
- **Lu / non lu** enregistré en base : sur l'accueil, une box par conversation
  non lue, dans les deux sens. Ouvrir la conversation la marque comme lue.
  - Un message de l'autre : « Kevin Arner vous a écrit ».
  - Une action de l'autre qui me concerne : la box affiche l'événement.
    - Pour le titulaire : « Kevin a accepté de prendre ta place. », « … a
      refusé… », « … ne peut finalement plus… », « … ne sera pas disponible
      en cas d'imprévu. », « … est de nouveau disponible… ».
    - Pour la personne de confiance : « Eliot a annulé sa demande. ».

    La demande reçue a déjà sa carte « Une demande t'attend », et la clôture
    automatique n'est pas une action de l'interlocuteur : elles n'ouvrent pas
    de box.
- Bouton « Appeler » dans la conversation.

---

## 7. Accueil (menu principal)

De haut en bout d'écran :

1. « Bonjour [Prénom] ».
2. Les demandes qui attendent une réponse (« UNE DEMANDE T'ATTEND »).
3. « Créer un Swend ».
4. « Mes Swends — N à venir », avec une pastille s'il y a une action à faire.
   Seuls comptent les Swends où je serai présent : titulaire, ou personne qui
   prend la place.
5. « ON COMPTE SUR TOI ».
6. « TON PROCHAIN SWEND ».
7. Les boxes non lues (messages, ou actions qui me concernent).
8. « Profil ».

Le profil contient aussi « Aide / Nous contacter » (suggestion de restaurant,
message au support).

---

## 8. Téléphone et comptes

- **L'identité d'une personne, c'est son compte**. Le téléphone ne sert qu'à
  **rapprocher** un numéro saisi et un compte.
- Tous les formats d'un même mobile sont équivalents : « 06 70 41 92 77 »,
  « 0670419277 », « +33 6 70 41 92 77 », « 0033… », « 06.70… ». La
  comparaison se fait sur la forme E.164 (+33670419277), identique en Dart et
  en SQL. Le numéro reste stocké tel que saisi.
- Seuls les **mobiles** sont acceptés. Un fixe ou un numéro trop court est
  refusé : « Numéro de mobile invalide… ». Les numéros étrangers sont acceptés
  avec leur indicatif.
- Refus immédiats dans les formulaires :
  - son propre numéro ;
  - le numéro de l'autre participant, comme personne de confiance ;
  - une personne déjà prévue de ce côté.

  La base refuse aussi ces cas, quel que soit le client.
- Le rattachement est automatique : quand quelqu'un crée son compte, les Swends
  et fiches qui portent son numéro lui sont reliés.
- Le numéro d'un compte est figé après l'inscription et n'est pas vérifié par
  SMS en V1 (risque connu).
- L'app **ne peut pas chercher un compte par numéro**, sauf un oui / non limité
  (20 numéros par 24 h) pour afficher « est déjà sur Swend » sur une personne
  qu'on est en train d'ajouter.

---

## 9. Notifications push

Elles sont envoyées :

- à un nouveau Swend reçu ;
- à chaque étape de la négociation et de la confirmation ;
- à un nouveau message ;
- à une demande reçue (« On a besoin de toi ») ;
- à une demande close (« C'est bon, quelqu'un a pu prendre la place. ») ;
- à la personne sollicitée quand le titulaire annule sa demande ;
- au titulaire quand sa personne de confiance :
  - accepte ;
  - refuse ;
  - se désiste ;
  - se déclare indisponible ;
  - redevient disponible ;
- à l'annulation pour double remplacement : push immédiate aux deux
  titulaires (« Ton Swend est annulé ») et aux deux remplaçants sélectionnés
  (« Le Swend est annulé »), sans jamais révéler qui remplace l'autre côté.
  L'acceptation qui déclenche cette annulation n'envoie pas en plus « … a
  accepté de prendre votre place ».

**Rappels automatiques (D-021)** : J-7, J-3 et J-1 à 18h, Jour J 3 heures
avant, en heure de Paris, pour les Swends scellés et actifs. Push uniquement.
Trois familles selon l'état de chaque côté au moment de l'envoi :
- « repas » pour qui vient réellement, avec l'autre titulaire officiel ;
- « remplacé » pour le titulaire dont quelqu'un a accepté la place (« Kevin
  prend ta place ») ;
- « cherche » pour le titulaire sans remplaçant accepté ayant une demande en
  attente, refusée ou désistée.

L'autre titulaire voit toujours le titulaire officiel. Pas de rattrapage,
jamais deux fois la même échéance. Au clic sur mobile, l'écran est choisi
selon l'état actuel (fiche du Swend, ou « Un imprévu ? » pour qui cherche
encore) ; sur le web, l'app s'ouvre sur l'accueil. Textes :
`PRODUCT_RULES.md` §9.7 et §9.8. **En ligne une fois la migration
`20260927040000_rappels_jour_j.sql` exécutée, la planification
(`supabase/planification/rappels_pg_cron.sql`) activée et l'app redéployée.**

Chaque notification d'action ouvre la conversation concernée. Les effets de bord
(clôtures, réouvertures) ne notifient jamais le titulaire. Il n'y a
**jamais** de notification à l'autre participant sur un remplacement.

---

## 10. Garanties assurées par la base (pas seulement par l'écran)

- La RLS limite chaque personne à ce qu'elle a le droit de voir : son côté, ou
  sa propre fiche.
- Toutes les transitions d'une demande passent par des fonctions SQL
  sécurisées qui vérifient qui appelle :
  - `envoyer_demande_remplacement` ;
  - `annuler_demande_remplacement` ;
  - `repondre_demande_remplacement` ;
  - `se_desister_du_remplacement` ;
  - `retirer_remplacant` ;
  - `ajouter_et_demander_remplacement` ;
  - `signaler_indisponibilite` / `signaler_disponibilite` (la personne
    elle-même, seulement si elle est simplement prévue).
- Consentement obligatoire : personne ne « prend la place » sans avoir accepté.
- Une seule personne par côté, même en cas de clics simultanés. Les actions
  concurrentes sont sérialisées par verrou.
- Un historique « qui a remplacé qui » est conservé dans des colonnes
  invisibles pour l'app.

---

## 11. Hors V1 / pas encore fait

- Deux remplaçants qui dînent ensemble : on annule à la place.
- Plusieurs restaurants au choix.
- Relances automatiques J-7 / J-3 / J-1.
- Notifications au titulaire pour une acceptation ou un désistement.
- Vérification du numéro par SMS.
- Changement de numéro par l'utilisateur.
- Envoi réel des photos.
- Analytics.
- Publication iOS / Android : seul le web est déployé.
- Statut `maintenu` (« Rendez-vous maintenu ») : il existe dans le modèle, mais
  rien ne le déclenche automatiquement aujourd'hui.

---

## 12. Règles de travail sur ce projet

- **Ne jamais écrire dans la base de production.** Les migrations SQL sont
  écrites dans `supabase/migrations/` puis **exécutées par le propriétaire du
  projet** dans l'éditeur SQL de Supabase, jamais par l'assistant.
- Ne jamais transmettre ni demander la clé `service_role` ou une clé privée
  Firebase.
- Rien de spécifique aux tests ne doit entrer dans la build de production :
  pas de faux compte, de sélecteur de rôle, de stub ni de contournement.
- Faire uniquement ce qui est demandé (« ne change rien d'autre »). Proposer
  plutôt qu'imposer tout choix produit nouveau.
- Avant de livrer : `flutter analyze`, puis le banc QA (`qa/run_metier.sh`,
  `qa/run_smoke.sh`, et `qa/run_full.sh` pour un lot important).
- Déploiement : build web, branche `gh-pages`, puis fast-forward de `main`
  (voir `ARCHITECTURE.md` §3).
- Mettre à jour `ARCHITECTURE.md` dans le même commit que tout changement de
  schéma, de règle de sécurité ou d'architecture.

---

## 13. Où regarder dans le code

| Sujet | Fichiers |
|---|---|
| Accueil | `lib/screens/root/menu_principal_screen.dart` |
| Liste « Mes Swends » | `lib/screens/accueil/accueil_screen.dart` |
| Création | `lib/screens/creer_pacte/creer_pacte_screen.dart` |
| Fiche d'un Swend | `lib/screens/detail_pacte/detail_pacte_screen.dart` (+ `bloc_*.dart`) |
| « Un imprévu ? » | `lib/screens/detail_pacte/imprevu_screen.dart` |
| « Modifier ma liste » | `lib/screens/detail_pacte/mes_remplacants_screen.dart` |
| Conversation | `lib/screens/detail_pacte/chat_screen.dart` |
| Rôle de l'utilisateur sur un Swend | `lib/models/perspective_pacte.dart` |
| Accès aux données | `lib/services/pacte_repository.dart` |
| Téléphone | `lib/utils/telephone.dart` (≡ `normaliser_telephone` en SQL) |
| Textes Messages / WhatsApp | `lib/utils/textes_invitation.dart`, `lib/widgets/envoi_invitation.dart` |
| Règles serveur | `supabase/migrations/*.sql` |
| Tests | `test/` (Dart), `qa/` (banc complet, voir `qa/README.md`) |
