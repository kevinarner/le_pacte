# SWEND — PRODUCT_RULES

> **Source de vérité produit**
>
> Ce document décrit les règles produit actuellement en vigueur pour Swend.
> Il décrit **ce que le produit doit faire**, indépendamment de l’état exact de l’implémentation à un instant donné.
>
> Les règles peuvent évoluer par décision explicite des fondateurs. Toute modification substantielle doit être reportée dans `DECISIONS.md`, puis répercutée dans l’implémentation et les tests QA.
>
> En cas d’écart avec `SWEND_README.md` :
> - `PRODUCT_RULES.md` décrit le comportement produit attendu ;
> - `SWEND_README.md` décrit principalement ce qui est implémenté aujourd’hui.

---

## 1. Définition d’un Swend

Un Swend est un rendez-vous scellé entre deux titulaires, autour d’un déjeuner ou d’un dîner, avec une date, une heure et un restaurant définis.

Une fois le Swend scellé, les titulaires ne rediscutent normalement plus du rendez-vous jusqu’au jour J.

Le principe fondamental est qu’un titulaire peut, en cas d’imprévu, se faire remplacer par une personne de confiance qu’il a préparée à l’avance, sans que l’autre titulaire en soit informé tant que le Swend continue.

Le mystère sur l’identité réelle de la personne présente le jour J fait partie du concept.

---

## 2. Vocabulaire officiel

Vocabulaire à privilégier dans l’interface :

- **Swend**
- **Créer un Swend**
- **Envoyer le Swend**
- **Scellé**
- **Jour J**
- **En cas d’imprévu**
- **prendre ta / votre place**
- **Lui demander**
- **Inviter et demander**
- **En attente**
- **Indisponible**
- **À vous de répondre**
- **En attente de [Prénom]**
- **Modifier ma liste**
- **Discuter**
- **Un imprévu ?**
- **On compte sur toi**
- **Une demande t’attend**

À éviter comme vocabulaire utilisateur :

- Pacte
- Confirmé
- Relais
- Suppléant
- Substitut
- Activer un remplaçant
- Quitter le Swend

Le code et la base peuvent conserver des termes historiques comme `pacte` ou `remplacant` tant que cela ne dégrade pas l’interface.

---

## 3. Cycle de vie d’un Swend

Le parcours conceptuel est :

**Créer → Envoyer → Répondre / choisir → Sceller**

### 3.1 Création

Le créateur choisit :

1. avec qui il souhaite faire le Swend ;
2. quand et où ;
3. ses personnes de confiance en cas d’imprévu.

Au moins 2 personnes de confiance sont requises au moment où le parcours concerné l’exige.

Les personnes de confiance choisies à la création ne sont activées qu’au scellage (voir 5.8).

### 3.2 Négociation de date

Le destinataire peut accepter une date proposée ou faire une contre-proposition.

Après la proposition initiale, il peut y avoir **au maximum 2 contre-propositions au total**, les deux titulaires confondus. Ce n’est pas 2 contre-propositions par personne.

Exemple :

1. Eliot propose A.
2. David propose B → contre-proposition n°1.
3. Eliot propose C → contre-proposition n°2.
4. David ne peut plus faire de nouvelle contre-proposition D.

À ce stade, David peut accepter C ; sinon le Swend est annulé.

Si aucun accord n’est trouvé après les 2 contre-propositions autorisées :

- le Swend est annulé ;
- il faut créer un nouveau Swend pour recommencer une négociation.

**Délai minimum (D-025).** Pour un Swend créé par un utilisateur standard, aucune date proposée (création ou contre-proposition) ni la date retenue ne peut tomber avant le jour de création, en heure de Paris, + 15 jours (créé le 1er octobre → première date possible le 16 octobre, à toute heure).

- Le calendrier ne propose rien avant la première date possible.
- Refus (par la base) : « Choisissez une date au moins 15 jours à l’avance. Première date possible : 16 octobre. »
- Comptes fondateurs (email confirmé du compte) : exemptés. L’exemption suit le Swend : un Swend créé par un fondateur l’est pour toute sa négociation ; un Swend créé par un utilisateur standard garde sa limite, même si le destinataire est fondateur.
- Pas de rétroactivité : les Swends créés avant la règle n’ont pas de limite.
- La date retenue doit aujourd’hui seulement respecter ce délai ; qu’elle soit l’une des dates proposées sera garanti par la base dans un lot ultérieur (D-025b).

### 3.3 Scellement

Une fois l’accord des deux titulaires obtenu, le Swend devient **Scellé**.

À partir de là, le rendez-vous n’est plus normalement rediscuté entre eux avant le jour J.

En V1, la réservation du restaurant n’est pas une condition préalable au scellage : le Swend est scellé dès que les deux participants se sont mis d’accord et que le destinataire confirme (voir 11.3).

### 3.4 Refus

Le destinataire peut refuser le Swend. Le Swend est alors annulé.

### 3.5 Annulation d’un Swend scellé (D-022)

Seuls les deux titulaires originaux peuvent annuler un Swend scellé. Un remplaçant ne peut jamais annuler : il peut seulement accepter ou refuser une demande, ou se désister. Un titulaire peut annuler même si quelqu’un a déjà accepté de prendre sa place.

L’annulation est possible jusqu’à l’heure prévue du rendez-vous. Ensuite, l’action `Annuler le Swend` n’est plus proposée (et la base la refuse). Ce qui se passe à l’heure du Swend est défini en 3.6 (D-023a).

#### Confirmation selon la situation de celui qui annule

**Aucun imprévu lancé.**

> **Vous ne pouvez plus être là ?**  
> Avant d’annuler, vous pouvez demander à quelqu’un de confiance de prendre votre place.

- action principale : `Trouver quelqu’un pour me remplacer` (ouvre « Un imprévu ? ») ;
- action secondaire : `Annuler malgré tout`, puis :

> **Annuler ce Swend ?**  
> Cette action mettra fin au Swend pour vous deux.

Actions : `Ne pas annuler` / `Annuler le Swend`.

**Déjà en recherche** (état D-021 « cherche » : au moins une demande en attente, refusée ou désistée, personne n’a accepté). Le parcours d’imprévu n’est pas reproposé.

> **Annuler ce Swend ?**  
> Les demandes de remplacement en cours seront annulées et le Swend prendra fin pour vous deux.

S’il ne reste plus de demande en attente (seulement des refus ou désistements) :

> **Annuler ce Swend ?**  
> Vous avez déjà cherché quelqu’un pour vous remplacer. Si vous annulez, le Swend prendra fin pour vous deux.

Actions : `Continuer à chercher` / `Annuler le Swend`. Toutes les demandes encore en attente sont clôturées.

**Quelqu’un a déjà accepté** (exemple : Kevin remplace Eliot).

> **Annuler ce Swend ?**  
> Kevin a accepté de prendre votre place.  
> Si vous annulez, le Swend prendra fin pour tout le monde.

Actions : `Ne pas annuler` / `Annuler le Swend`.

#### Effet

Le Swend est annulé immédiatement, en une seule opération côté serveur (statut, clôture des demandes en attente, notifications). Aucun motif n’est demandé. Swend enregistre qui a annulé et quand, sans l’afficher (donnée réservée à un usage futur ; inconnue pour les annulations antérieures, jamais reconstituée). Celui qui annule voit :

> **Swend annulé**  
> Votre Swend avec [Prénom] est annulé.

#### Notifications

| Destinataire | Titre | Message |
|---|---|---|
| Autre titulaire | Ton Swend est annulé | [Prénom] a annulé votre Swend du lundi 13 octobre à 20h00 · Au Père Lapin. |
| Remplaçant ayant accepté | Le Swend est annulé | [Prénom] a annulé le Swend du lundi 13 octobre à 20h00 · Au Père Lapin. |
| Personne dont la demande était en attente | La demande n’est plus d’actualité | Le Swend a été annulé. |

- Aucun motif n’est communiqué.
- [Prénom] = le titulaire qui a annulé. Le remplaçant ayant accepté l’apprend (exemple : Kevin devait remplacer Eliot et David annule → « David a annulé le Swend du … ») : une fois le Swend annulé, l’expérience est terminée et il vaut mieux qu’il comprenne d’où vient l’annulation. Une personne dont la demande était seulement en attente ne l’apprend pas.
- Une personne seulement prévue, jamais sollicitée, ne reçoit rien ; le Swend disparaît de `On compte sur toi`.
- Une demande en attente est clôturée (événement « La demande n’est plus d’actualité » dans le fil).
- L’identité d’un remplaçant n’est jamais révélée à l’autre titulaire.
- Les conversations existantes (titulaire ↔ personnes de confiance) passent immédiatement en lecture seule (D-023a). Elles restent lisibles par les titulaires (toutes celles de leur côté) et par le remplaçant sélectionné (la sienne) ; les autres personnes de confiance n’y ont plus accès (voir 3.6). Il n’existe pas de chat entre les deux titulaires.

#### Réservation

Pour l’utilisateur, l’annulation de la réservation est gérée par Swend : on ne lui demande jamais d’appeler ou de prévenir le restaurant. En interne, l’équipe Swend gère cette annulation manuellement (voir 11.3).

#### Historique

Un Swend annulé ne disparaît pas. `Mes Swends` sépare :

- **À venir** : Swends actifs ;
- **Passés et annulés** : Swends dont l’heure est passée et Swends annulés.

Une carte annulée est grisée, affiche clairement `Annulé` et ne donne jamais l’impression d’être encore active ou actionnable. Un Swend annulé reste dans l’historique des deux titulaires et du remplaçant qui avait accepté ; il n’apparaît plus pour les personnes seulement prévues, sollicitées ou ayant refusé.

Un Swend scellé (actif, passé ou annulé) ne peut plus être supprimé par un utilisateur. Un Swend jamais scellé peut toujours être supprimé par ses titulaires.

### 3.6 À l’heure du Swend : gel (D-023a)

À l’heure prévue du Swend, l’état du rendez-vous est figé. À partir de ce moment, on ne gère plus l’imprévu ; on entre dans l’après-Swend. L’heure du serveur et la date du Swend font foi, jamais l’horloge de l’appareil.

#### Plus aucune action d’imprévu

À partir de l’heure du Swend, plus rien ne peut modifier la situation :

- envoyer une demande de remplacement ;
- annuler une demande ;
- accepter ou refuser une demande ;
- se désister ;
- ajouter quelqu’un et lui demander ;
- signaler une disponibilité ou une indisponibilité ;
- ajouter ou retirer une personne de confiance ;
- annuler le Swend (déjà la règle de 3.5).

L’application masque ces actions. Si elle en affiche encore une brièvement (horloge de l’appareil en retard), le serveur la refuse et l’utilisateur voit :

> L’heure du Swend est passée : cette action n’est plus possible.

#### Demandes encore en attente

Toute demande encore en attente à l’heure du Swend est clôturée automatiquement (au plus quelques minutes après). La personne sollicitée reçoit une push :

| Titre | Message |
|---|---|
| La demande n’est plus d’actualité | L’heure du Swend est passée. |

- Une seule push par personne, même si elle était sollicitée des deux côtés.
- Le titulaire qui cherchait quelqu’un ne reçoit pas de push spécifique.
- Jamais « C’est bon, quelqu’un a pu prendre la place ».
- Si le traitement automatique a plus de 12 heures de retard (panne), la demande est clôturée sans push tardive.

#### Conversations de l’imprévu

À l’heure du Swend, toutes les conversations titulaire ↔ personne de confiance du Swend passent en lecture seule : lecture et historique conservés, aucun nouveau message possible.

Une conversation qui a réellement eu une activité (un message ou un événement) reçoit un dernier événement système :

> Le Swend a commencé.  
> Cette conversation est désormais terminée.

- Cet événement ne crée jamais de « non lu ».
- Une conversation vierge ne reçoit rien : elle devient simplement non modifiable.
- Un Swend annulé : ses conversations passent en lecture seule dès l’annulation (sans cet événement).
- Relecture : sur la fiche d’un Swend passé ou annulé, `Relire une conversation` propose au titulaire les conversations qui ont eu une activité (ouverte directement s’il n’y en a qu’une, sinon choix) ; la personne de confiance qui garde le Swend dans son historique a `Relire la conversation`. Les conversations vierges ne sont jamais proposées. Aucune écriture possible.

#### Swend passé

- Le Swend n’est pas « terminé » en base : il reste scellé (`confirme`) ; « passé » se déduit de son heure. Aucun indicateur du profil (Fiabilité, Swends réalisés, Remplacements) n’est modifié.
- Il rejoint automatiquement `Passés et annulés`, sans confirmation ni badge particulier (`Réalisé`, `Terminé`, `En attente`…).
- Il reste dans l’historique des deux titulaires et du remplaçant sélectionné encore actif à l’heure du Swend.
- Il disparaît pour les personnes seulement prévues, sollicitées, ayant refusé ou s’étant désistées (`Mes Swends`, `On compte sur toi`, `Une demande t’attend`, box de l’accueil).

#### Accès une fois le Swend passé ou annulé

- Les deux titulaires gardent le Swend et peuvent relire toutes les conversations de leur côté qui ont eu une activité, y compris avec une personne qui n’a finalement pas participé.
- Le remplaçant effectivement sélectionné garde le Swend dans son historique et peut relire sa propre conversation (en cas de double remplacement, chacun des deux).
- Une personne seulement prévue, sollicitée, ayant refusé ou s’étant désistée n’a plus accès au Swend ni à sa conversation, ni à aucune donnée du Swend, y compris le numéro de téléphone du titulaire. Les données restent conservées ; seul son accès disparaît.
- Une personne retirée de la liste n’a plus accès, à aucun moment ; un utilisateur extérieur n’a jamais accès.
- Avant l’heure du Swend, sur un Swend en cours, chaque personne de confiance non retirée garde les accès de son rôle.
- Garanti par la base (RLS), pas seulement par l’écran.
- Un rappel cliqué après l’heure du Swend ouvre la fiche, jamais `Un imprévu ?`.

#### Invariants

- Un Swend ne peut jamais être scellé si sa date est déjà passée.
- La date d’un Swend scellé ne peut plus être modifiée par l’application.
- Retirer une personne de confiance ne détruit jamais sa conversation : elle est archivée avec son historique.
- Les Swends déjà passés au moment de la mise en place de cette règle sont considérés comme déjà traités : aucune push, aucun événement rétroactif.

L’après-Swend : chat après le Swend (D-023b, §3.7, en production depuis le 30/09) ; « Faire un nouveau Swend » et fermeture du chat (D-023c, §3.8, implémenté, pas encore en production).

### 3.7 Chat après le Swend (D-023b)

Après un Swend qui a eu lieu, le silence est levé : un chat s’ouvre automatiquement.

#### Ouverture

- H+3 si H+3 tombe au plus tard à 23:00 (heure de Paris) le jour du Swend ; sinon 10:00 le lendemain. Exemples : 12h → 15h ; 20h → 23h ; 20h01, 20h30, 22h → lendemain 10h.
- Le chat et sa notification deviennent disponibles au même moment ; rien n’existe avant.
- Jamais de chat pour un Swend annulé (y compris annulation pour double remplacement).
- Pas de rattrapage : un Swend dont l’ouverture tombe avant la mise en service de D-023b n’a pas de chat.
- Si l’ouverture est traitée en retard, le chat s’ouvre quand même ; la notification seulement si le retard ne dépasse pas 12 heures.

Notification (une par participant, sans rappel) :

> Alors, ce Swend ?
> Le silence est levé. Vous pouvez maintenant en reparler dans le chat.

#### Participants (3 au plus)

- Les deux titulaires d’origine, et le remplaçant sélectionné à l’heure du Swend s’il existe. Le titulaire remplacé reste membre.
- Jamais : une personne seulement prévue, sollicitée non choisie, ayant refusé, désistée ou retirée ; si quelqu’un a accepté puis s’est désisté, seul le remplaçant final participe.
- Prénom du compte, figé à l’ouverture ; compte supprimé plus tard : « Compte supprimé », historique conservé.

#### Révélation (à partir de l’ouverture seulement)

- Titulaire remplacé : `Kevin a pris votre place.`
- Autre titulaire : `Kevin a pris la place d’Eliot.`
- Remplaçant (tutoyé, comme toute personne de confiance) : `Tu as pris la place d’Eliot.`
- Le Swend reste nommé d’après ses titulaires d’origine.

#### Placement

Pas d’onglet ni de liste de conversations : accès depuis le Swend.

- Fiche d’un Swend passé : bloc `APRÈS LE SWEND` (au-dessus de la relecture de l’imprévu), seulement une fois le chat ouvert : `Discuter` / `David vous a écrit`, puis `Avec David` / `Avec David et Kevin`, puis `Faire un nouveau Swend` (D-023c, §3.8). Chat fermé : voir §3.8.
- Mes Swends : `Discuter`, `● David vous a écrit`, `Voir la conversation` (chat fermé, D-023c), `Annulé`. Aucun statut `Réalisé` / `Terminé` ; ordre chronologique inchangé.
- Accueil : tant que je n’ai jamais ouvert le chat, `Alors, ce Swend ?` / `Le silence est levé.` ; ensuite, s’il y a des messages non lus, `David vous a écrit` (ou `4 nouveaux messages` dans un chat à 2 ; dernier expéditeur dans un chat à 3) / `Après le Swend · Au Père Lapin · 13 octobre`. Jamais le contenu. 2 cartes au plus, triées par dernier message. Priorité : urgences des Swends en cours (y compris l’imprévu), puis après le Swend, puis prochain Swend.
- Entre l’heure du Swend et l’ouverture : aucun nouveau libellé, aucun bloc.

#### Chat

- En-tête : `Swend au Père Lapin` / `Après le Swend`, puis `Eliot · David` ou `Eliot · David · Kevin`.
- Premier affichage sans message : `À vous de débriefer.` (aucun message système d’ouverture).
- Texte et emoji, 2 000 caractères au plus. Pas d’image, GIF, réaction, pièce jointe, vocal, modification, suppression, « Quitter », « Vu à… », « en train d’écrire », présence.
- Prénom au-dessus des bulles seulement à 3 ; aucun badge « remplaçant ».
- Lecture strictement individuelle.
- Nouveau message : `[Prénom] vous a écrit` / `Après le Swend · [Restaurant]`, à chacun des autres ; jamais le contenu, jamais de numéro. Le clic ouvre directement le chat (mobile et web) ; sans accès : `Cette conversation n’est plus accessible.`
- Sans limite de temps côté produit ; historique conservé avec le Swend.

Fermeture par un nouveau Swend scellé : §3.8 (D-023c).

### 3.8 Faire un nouveau Swend, fermeture du chat (D-023c)

#### Fermeture du chat, au scellement seulement

- Dès qu’un nouveau Swend devient **scellé**, chaque chat après le Swend déjà ouvert où ses **deux** personnes sont participantes ensemble est fermé définitivement : titulaire ↔ titulaire, titulaire ↔ remplaçant, remplaçant ↔ autre participant, chat à 2 ou à 3. Un chat où une seule des deux participe reste ouvert.
- Décidé par la base au scellement, quel que soit le point d’entrée (`Faire un nouveau Swend`, `Créer un Swend` depuis l’accueil, tout autre). Une invitation ou une négociation ne ferme rien.
- Chat fermé : lecture seule définitive, historique entier conservé. Un message système, une seule fois, à sa place chronologique, sans heure dans le texte :
  > Un nouveau Swend a été scellé.
  > Ce chat est désormais fermé pour préserver le silence.
  Un scellement ultérieur par une autre paire du même chat n’ajoute rien.
- Définitive : jamais de réouverture, même si le nouveau Swend est annulé quelques secondes après ; le message système reste ; aucun message d’annulation dans l’ancien chat.
- Négociations parallèles : le premier scellement ferme ; les autres négociations continuent normalement, peuvent être scellées plus tard, sans second message.
- Aucune notification de fermeture : le message système suffit.

#### Chat pas encore ouvert

- Si un nouveau Swend est scellé entre deux personnes avant l’heure d’ouverture du chat d’un Swend précédent (date antérieure) dont elles sont participantes potentielles (les deux titulaires et le remplaçant sélectionné s’il existe, même règle que l’ouverture), ce chat ne s’ouvre jamais : aucun faux chat fermé, aucun message système, aucun accès à une conversation. Le Swend passé reste consultable.

#### Faire un nouveau Swend (fiche « Après le Swend », chat ouvert)

- Sous `Discuter`, une action secondaire `Faire un nouveau Swend` (sur la fiche, jamais dans le fil du chat).
- Chat à 2 : directement `Quand et où ?` avec l’autre personne (pas d’étape `Avec qui ?`) ; date, restaurant et personnes de confiance repartent de zéro. La personne est désignée par son identité serveur, jamais par un numéro (D-024). Si un Swend est déjà en cours entre les deux : `Un Swend est déjà en cours entre vous.`
- Chat à 3 : `Avec qui veux-tu faire un nouveau Swend ?` avec seulement les deux autres personnes, au même niveau (aucun libellé titulaire ou remplaçant), sans recherche, sans ajout, sans bouton `Continuer`. Toucher une personne disponible mène à `Quand et où ?`. Une personne avec qui un Swend est déjà en cours est désactivée : `Tu as déjà un Swend en cours avec Kevin.` ; l’autre reste choisissable.
- Un seul Swend en cours par paire, règle globale garantie par la base, quel que soit le point d’entrée : `Faire un nouveau Swend` comme `Créer un Swend` depuis l’accueil (une personne sans compte est reconnue par son numéro). Toute tentative de doublon est refusée, dans un sens comme dans l’autre ; textes : `Un Swend est déjà en cours entre vous.` (création à 2 ou depuis l’accueil), `Tu as déjà un Swend en cours avec Kevin.` (choix à 3). En cours : en négociation avec au moins une date proposée à venir, ou scellé et pas encore passé ; une fois le Swend précédent passé ou annulé, un nouveau peut être créé.

#### Après la fermeture

- Fiche du Swend passé : `Voir la conversation` (au lieu de `Discuter`), plus de `Faire un nouveau Swend`, et sobrement `Conversation fermée` / `Un nouveau Swend a été scellé. Ce chat est désormais fermé pour préserver le silence.`
- Conversation : historique lisible, message système dans le fil, aucune zone de saisie (`Conversation fermée` à sa place), aucun moyen de rouvrir.
- Mes Swends passés : pas de statut lourd (`Voir la conversation`).
- Textes de D-023c au tutoiement.

---

## 4. Rôles

### 4.1 Titulaires

Les deux participants officiels du Swend sont les titulaires :

- initiateur ;
- destinataire.

Chaque titulaire possède son propre côté du Swend et sa propre liste de personnes de confiance.

### 4.2 Personne de confiance prévue

Une personne simplement prévue :

- est rattachée à un seul côté du Swend ;
- peut voir son rôle sur son propre compte, une fois le Swend scellé (voir 5.8) ;
- n’est pas encore engagée à venir ;
- ne compte pas comme participante à un Swend à venir ;
- peut discuter avec le titulaire si elle possède un compte Swend.

### 4.3 Personne sollicitée

Lorsqu’un titulaire a réellement un imprévu, une personne prévue peut être sollicitée pour prendre sa place.

Elle peut alors accepter ou refuser.

### 4.4 Personne ayant accepté

Une personne ayant accepté prend physiquement la place du titulaire le jour J.

Elle ne devient pas administratrice du Swend.

Elle ne peut pas :

- modifier la date ;
- modifier le restaurant ;
- annuler le Swend ;
- gérer la liste du titulaire ;
- choisir son propre remplaçant ;
- contacter l’autre titulaire avant le jour J.

**Prendre la place ≠ prendre le contrôle du Swend.**

### 4.5 Titulaire remplacé

Le titulaire original reste responsable du Swend jusqu’au jour J, même lorsqu’une autre personne a accepté de prendre sa place.

---

## 5. Personnes de confiance

Chaque titulaire prépare sa propre liste de personnes susceptibles de prendre sa place.

Cette liste est invisible pour l’autre titulaire principal.

### 5.1 Taille de la liste

Il n’existe pas de plafond produit total de 5 personnes de confiance.

Un formulaire peut limiter le nombre de nouvelles saisies en une seule opération, mais l’utilisateur doit pouvoir ajouter d’autres personnes ensuite.

L’interface ne doit pas laisser croire qu’il existe une limite totale de 5 personnes.

### 5.2 Personne déjà sur Swend

Pour une personne explicitement ajoutée par l’utilisateur, l’application peut indiquer :

> Kevin est déjà sur Swend

ou :

> Kevin n’a pas encore Swend

Cette information sert à déterminer si une invitation est nécessaire.

Elle ne doit pas devenir un outil général permettant de tester arbitrairement si n’importe quel numéro possède un compte.

### 5.3 Modifier ma liste

`Modifier ma liste` est un parcours de préparation et de gestion.

Il permet notamment de :

- voir toutes les personnes prévues ;
- voir leur statut ;
- ajouter une personne ;
- retirer une personne lorsque l’état le permet (sa conversation et son historique sont conservés, D-023a) ;
- inviter une personne qui n’a pas encore Swend.

Ce parcours ne doit pas envoyer de demande de remplacement.

### 5.4 Discuter

`Discuter` permet au titulaire d’accéder aux conversations avec ses personnes de confiance ayant un compte Swend.

Cet accès reste disponible même après qu’une personne a accepté de prendre sa place.

La sélection d’un remplaçant ne coupe jamais l’accès aux autres conversations.

### 5.5 Indisponibilité spontanée avant sollicitation

Une personne simplement prévue peut signaler :

> Je ne serai pas disponible

Elle devient alors **Indisponible** pour ce Swend afin que le titulaire puisse anticiper et ajouter d’autres personnes.

Le titulaire est informé que cette personne ne sera pas disponible.

Tant qu’elle n’a pas refusé une vraie demande, cette indisponibilité reste réversible :

> Je suis finalement disponible

Elle redevient alors disponible dans la liste du titulaire.

Distinction produit :

- indisponibilité spontanée avant demande = **réversible** ;
- refus d’une vraie demande = **non réversible pour ce Swend** ;
- acceptation puis désistement = **non réversible pour ce Swend**.

### 5.6 Ordre d’affichage

Lorsque des personnes avec et sans compte Swend sont affichées ensemble :

1. personnes ayant déjà un compte Swend ;
2. personnes n’ayant pas encore Swend.

À l’intérieur de chaque groupe, conserver l’ordre existant.

### 5.7 Exclusions

Un titulaire ne peut pas ajouter :

- lui-même ;
- l’autre titulaire du Swend.

Cette règle doit être garantie côté serveur.

### 5.8 Activation après scellage

Une personne de confiance peut être choisie et configurée pendant la création du Swend, mais elle n’est activée qu’une fois le Swend scellé.

Tant que le Swend n’est pas scellé :

- aucune notification automatique à la personne de confiance ;
- rien dans `On compte sur toi` ;
- aucun accès au Swend en tant que personne de confiance ;
- aucune conversation contextuelle accessible de son côté.

Au moment où le Swend devient scellé :

- la personne de confiance devient active ;
- elle apparaît dans `On compte sur toi` ;
- les notifications prévues peuvent alors être envoyées.

Si le Swend est refusé, annulé ou si la négociation n’aboutit jamais :

- la personne de confiance ne doit jamais être informée automatiquement ;
- elle ne doit jamais voir ce Swend.

Un partage manuel (Messages / WhatsApp) que l’utilisateur choisit volontairement d’envoyer n’est pas une information automatique.

Cette règle doit être garantie côté serveur.

---

## 6. « Un imprévu ? »

`Un imprévu ?` signifie que le titulaire a réellement besoin de quelqu’un pour prendre sa place.

Ce parcours est distinct de :

- `Modifier ma liste` ;
- `Discuter`.

### 6.1 Personne déjà sur Swend

Action :

> Lui demander

Une confirmation légère peut être affichée avant l’envoi.

### 6.2 Personne sans compte

Une personne sans compte reste une solution possible.

Action :

> Inviter et demander

Cette action combine :

- l’invitation à rejoindre Swend ;
- la demande réelle de prendre la place.

Il ne faut pas imposer un parcours :

**inviter → attendre → revenir → demander**.

Le message doit indiquer à la personne qu’elle doit créer son compte avec le numéro sur lequel elle reçoit l’invitation pour retrouver correctement la demande.

### 6.3 Plusieurs demandes simultanées

Plusieurs personnes peuvent être sollicitées en parallèle.

Il n’existe pas d’ordre de priorité obligatoire.

### 6.4 Première acceptation gagnante

La première personne qui accepte obtient la place de manière atomique.

À cet instant :

- elle devient sélectionnée ;
- les autres demandes encore en attente sont clôturées ;
- aucune deuxième acceptation ne doit pouvoir réussir.

Cette garantie doit être assurée côté serveur.

### 6.5 Annuler une demande

Tant qu’une personne n’a pas accepté, le titulaire peut annuler sa demande.

Après annulation :

- la personne redevient disponible ;
- elle peut être sollicitée à nouveau ;
- l’ancienne demande ne peut plus être acceptée.

### 6.6 Ajouter quelqu’un pendant l’imprévu

Le titulaire peut ajouter une nouvelle personne pendant le parcours d’imprévu.

L’ajout et la demande doivent être réalisés dans un même parcours simple.

Il n’existe pas de plafond produit total.

L’annulation du Swend reste une solution de dernier recours.

---

## 7. États d’une demande

### 7.1 Disponible / non sollicitée

La personne est prévue mais n’a pas encore été sollicitée.

Elle peut apparaître comme :

- `Lui demander` ;
- `Inviter et demander` si elle n’a pas encore de compte.

### 7.2 En attente

Une demande a été envoyée et la personne n’a pas encore répondu.

Côté titulaire :

> En attente

Côté personne sollicitée :

> Une demande t’attend

Elle peut :

- accepter ;
- refuser ;
- écrire au titulaire.

### 7.3 Refusée

Une personne ayant refusé devient :

> Indisponible

Elle ne redevient pas automatiquement sollicit-able plus tard sur ce Swend.

### 7.4 Acceptée

La personne prend la place du titulaire.

Toutes les autres demandes encore en attente sont clôturées automatiquement.

Le titulaire initial ne peut pas reprendre sa place simplement parce que son imprévu disparaît.

### 7.5 Clôturée automatiquement

Une demande clôturée uniquement parce qu’une autre personne a accepté n’est pas équivalente à un refus.

Si la personne sélectionnée se désiste ensuite :

- cette ancienne demande peut redevenir sollicit-able ;
- la personne revient à `Lui demander` ;
- aucune demande n’est renvoyée automatiquement.

Le titulaire doit explicitement solliciter la personne à nouveau.

### 7.6 Désistement après acceptation

Une personne ayant accepté peut ensuite indiquer :

> Je ne peux finalement plus venir

Elle devient alors **Indisponible** pour ce Swend.

Elle ne redevient pas sollicit-able.

Elle n’a plus de rôle actif côté tiers et doit disparaître notamment :

- de `On compte sur toi` ;
- de `Mes Swends` pour ce rôle ;
- de `Ton prochain Swend` ;
- du compteur de Swends à venir.

Elle reste visible côté titulaire dans `Modifier ma liste` avec le statut `Indisponible`.

La recherche est rouverte côté titulaire.

### 7.7 Aucun candidat disponible

La fiche principale ne doit pas présenter comme disponibles :

- les personnes ayant refusé ;
- les personnes ayant accepté puis s’étant désistées ;
- les personnes s’étant déclarées spontanément indisponibles tant qu’elles n’ont pas réactivé leur disponibilité.

Si personne n’est disponible :

> Aucune personne disponible pour le moment.

`Modifier ma liste` et `Discuter` restent accessibles.

---

## 8. Confidentialité

La confidentialité du remplacement est une règle fondamentale de Swend.

### 8.1 Principe général

Tant que le Swend continue, un titulaire principal ne doit rien savoir des démarches de remplacement de l’autre côté.

Exemple : Eliot cherche quelqu’un pour prendre sa place. David ne doit rien savoir.

### 8.2 Ce qui reste invisible à l’autre titulaire

L’autre titulaire ne doit recevoir aucun indice concernant :

- l’ouverture de `Un imprévu ?` ;
- les personnes de confiance de l’autre côté ;
- les demandes envoyées ;
- les conversations avec les personnes de confiance ;
- les refus ;
- les acceptations ;
- les désistements ;
- les ajouts de nouvelles personnes ;
- l’identité de la personne sélectionnée.

Sa fiche du Swend doit rester inchangée tant que le Swend continue.

### 8.3 Même personne des deux côtés

Une même personne peut figurer dans les listes des deux titulaires.

Si elle accepte de remplacer Eliot :

- elle devient indisponible côté David ;
- David voit uniquement `Indisponible` ;
- aucune raison ne lui est donnée ;
- aucune notification révélatrice ne lui est envoyée.

Elle ne peut jamais prendre les deux places.

### 8.4 Conversations privées

Une conversation entre un titulaire et une personne de confiance n’est accessible qu’aux personnes autorisées.

L’autre titulaire ne doit pas pouvoir lire :

- les messages ;
- les événements système ;
- les états internes liés à la demande.

Cette règle doit être garantie côté serveur / RLS et pas uniquement par l’interface.

### 8.5 Double remplacement

Si les deux titulaires ont chacun une personne sélectionnée pour les remplacer, le Swend est annulé en V1.

Les deux titulaires peuvent connaître la raison générale :

> Vous avez chacun fait appel à quelqu’un pour prendre votre place.

L’identité des remplaçants n’a pas besoin d’être révélée.

Au moment de l’annulation automatique, une push immédiate part (voir 9.8) : aux deux titulaires et à chaque remplaçant sélectionné. Elle ne révèle jamais à un côté qui remplace l’autre côté. Aucun rappel n’est ensuite envoyé.

---

## 9. Chat et notifications

Le chat est contextuel à un Swend et à la relation entre un titulaire et une personne de confiance.

Swend ne doit pas devenir une messagerie générale autonome.

### 9.1 Accès aux conversations

Une personne de confiance ayant un compte Swend peut discuter avec le titulaire avant même d’être sollicitée.

Le même fil continue pendant tous les changements d’état :

**prévue → sollicitée → acceptée / refusée → éventuellement désistée**.

On ne crée pas un nouveau fil à chaque transition.

### 9.2 Conservation après sélection d’un remplaçant

Lorsqu’une personne a accepté, le titulaire conserve :

- `Écrire à [Prénom]` avec la personne sélectionnée ;
- `Discuter` avec l’ensemble de ses autres personnes de confiance ayant Swend.

La sélection d’une personne ne coupe jamais les autres conversations.

### 9.3 Lu / non lu

Les messages non lus sont gérés par conversation.

Si plusieurs personnes écrivent au titulaire, plusieurs alertes peuvent coexister.

Ouvrir une conversation marque uniquement cette conversation comme lue.

Les propres messages de l’utilisateur ne génèrent pas d’alerte non lue pour lui-même.

L’état lu / non lu est persistant en base.

### 9.4 Événements système

Les changements importants apparaissent dans le fil sous forme d’événements système persistants, horodatés et visuellement distincts des messages humains.

Au minimum :

- demande envoyée ;
- demande annulée ;
- refus ;
- acceptation ;
- désistement ;
- clôture automatique ;
- fin de la conversation à l’heure du Swend (« Le Swend a commencé. Cette conversation est désormais terminée. », D-023a, voir 3.6).

### 9.5 Formulation selon le lecteur

Un même événement peut être formulé différemment selon la personne qui le lit.

Exemple côté titulaire :

> Kevin a accepté de prendre ta place.

Exemple côté Kevin :

> Tu as accepté de prendre la place d’Eliot.

Lors d’une clôture automatique, ne pas révéler qui a obtenu la place :

> La demande n’est plus d’actualité.

### 9.6 Notifications liées aux actions directes

Lorsqu’une action concerne directement un autre utilisateur, celui-ci doit être informé :

- dans l’application ;
- par notification push.

Exemples :

- nouveau Swend reçu ;
- étape de négociation qui nécessite une réponse ;
- nouveau message ;
- demande de remplacement reçue ;
- demande annulée ;
- acceptation ;
- refus ;
- désistement ;
- clôture automatique d’une demande ;
- annulation liée au double remplacement ;
- annulation manuelle du Swend par un titulaire (voir 3.5).

Les textes exacts, regroupements éventuels et priorités de push peuvent être affinés ultérieurement.

### 9.7 Rappels automatiques (D-021)

Les rappels liés au temps sont distincts des notifications déclenchées par une action directe d’un utilisateur.

#### Cadence et horaires

Pour chaque Swend scellé :

- J-7 à 18h ;
- J-3 à 18h ;
- J-1 à 18h ;
- Jour J, 3 heures avant le rendez-vous.

Toutes les heures sont calculées en Europe/Paris en V1 (changements d’heure compris). J-7, J-3 et J-1 sont des jours du calendrier Europe/Paris ; le Jour J est exactement 3 heures avant la date et l’heure du rendez-vous.

#### Nature

- Push uniquement : aucune box ni aucun état supplémentaire dans l’app.
- Chaque rappel mentionne toujours la date, l’heure et le restaurant.
- Aucun rappel pour un Swend non scellé, annulé, annulé par double remplacement ou autrement inactif.
- Pas de rattrapage : une échéance déjà passée au moment où le Swend est scellé ou découvert est ignorée (ex. un Swend scellé à J-2 ne reçoit jamais J-7 ni J-3, mais reçoit J-1 et le Jour J).
- Une même échéance n’est envoyée qu’une seule fois à une même personne pour un même Swend (garanti par le backend).

#### Trois familles de rappels

Pour chaque côté du Swend, l’état du titulaire est évalué au moment de chaque envoi :

- **Normal** : il vient lui-même → il reçoit les rappels « repas » avec l’autre titulaire.
- **Remplacé** : une personne a accepté de prendre sa place → cette personne reçoit les rappels « repas » avec l’autre titulaire ; le titulaire reçoit les rappels « remplacé » (« Kevin prend ta place », avec le prénom de la personne actuellement sélectionnée).
- **Cherche un remplaçant** : personne n’a accepté, et au moins une demande de ce côté est en attente, refusée ou désistée → le titulaire reçoit les rappels « cherche ». Annuler toutes ses demandes en attente (sans refus ni désistement) le ramène à l’état normal.

L’autre titulaire reçoit toujours les rappels « repas » avec le prénom du titulaire officiel : il ne découvre jamais par un rappel qu’un remplacement a eu lieu ou est cherché.

Textes validés (exemple : lundi 13 octobre à 20h00 · Au Père Lapin).

Rappels « repas » ([prénom] = l’autre titulaire officiel) :

| Échéance | Titre | Message |
|---|---|---|
| J-7 | Le compte à rebours est lancé | Votre Swend avec [prénom] approche : lundi 13 octobre à 20h00 · Au Père Lapin. |
| J-3 | Ça se rapproche… | Plus que 3 jours avant votre Swend avec [prénom] : lundi 13 octobre à 20h00 · Au Père Lapin. |
| J-1 | C’est demain ! | Votre Swend avec [prénom], c’est demain : lundi 13 octobre à 20h00 · Au Père Lapin. |
| Jour J | C’est le jour du Swend ! | Rendez-vous à 20h00 · Au Père Lapin. Est-ce que tu vas vraiment [déjeuner/dîner] avec [prénom] ? |

Rappels « remplacé » (au titulaire remplacé, [Kevin] = la personne qui prend sa place) :

| Échéance | Titre | Message |
|---|---|---|
| J-7 | Ton Swend approche | Lundi 13 octobre à 20h00 · Au Père Lapin. / Kevin prend ta place. |
| J-3 | Plus que 3 jours | Ton Swend est prévu lundi 13 octobre à 20h00 · Au Père Lapin. / Kevin prend ta place. |
| J-1 | C’est demain ! | Ton Swend aura lieu lundi 13 octobre à 20h00 · Au Père Lapin. / Kevin prend ta place. |
| Jour J | C’est le jour du Swend ! | Aujourd’hui, lundi 13 octobre à 20h00 · Au Père Lapin. / Kevin prend ta place. |

Rappels « cherche » ([prénom] = l’autre titulaire officiel) :

| Échéance | Titre | Message |
|---|---|---|
| J-7 | Ton Swend avec [prénom] approche | Lundi 13 octobre à 20h00 · Au Père Lapin. / Tente de trouver quelqu’un pour te remplacer tant qu’il en est encore temps. |
| J-3 | Plus que 3 jours pour ton Swend avec [prénom] | Lundi 13 octobre à 20h00 · Au Père Lapin. / Tente de trouver quelqu’un pour te remplacer tant qu’il en est encore temps. |
| J-1 | C’est demain ! | Ton Swend avec [prénom] : lundi 13 octobre à 20h00 · Au Père Lapin. / Le temps presse, essaie de trouver quelqu’un pour te remplacer au plus vite. |
| Jour J | Ton Swend avec [prénom] est dans 3h ! | Aujourd’hui à 20h00 · Au Père Lapin. / Ton Swend est en péril ! Trouve quelqu’un pour te remplacer dès que possible. Et si vraiment personne n’est disponible, annule le Swend pour que le restaurant soit prévenu. |

(« / » = retour à la ligne.)

#### Changement de rôle entre deux rappels

Les destinataires et la famille sont recalculés au moment de chaque envoi ; aucun rappel déjà passé n’est renvoyé. Exemples :

- Kevin accepte après J-3 : aucun J-3 rétroactif, il reçoit les rappels suivants.
- Kevin se désiste : plus aucun rappel pour lui ; le titulaire repasse en « cherche » ; l’autre titulaire continue ses rappels normaux.
- Sylvain accepte ensuite : Sylvain reçoit les rappels « repas » suivants ; le titulaire reçoit « Sylvain prend ta place ».

#### Clic sur un rappel

La destination est déterminée selon l’état actuel du Swend au moment du clic, jamais figée dans la notification :

- participant normal → fiche du Swend ;
- remplaçant accepté → sa fiche de remplaçant ;
- titulaire remplacé → fiche du Swend ;
- titulaire qui cherche encore quelqu’un → « Un imprévu ? ».
- personne qui n’a plus accès au Swend (ex. désistée) → accueil.
- après l’heure du Swend : jamais « Un imprévu ? » (fiche du Swend), D-023a.

Même comportement sur le web et sur mobile. Sur le web, l’app s’ouvre sur la page de connexion si besoin, puis sur la destination.

### 9.8 Double remplacement : push immédiate

Ce n’est pas un rappel programmé. Quand le Swend est automatiquement annulé parce que les deux titulaires ont chacun un remplaçant accepté, une push immédiate part :

- à chaque titulaire — titre « Ton Swend est annulé », message « Toi et [prénom] avez chacun fait appel à quelqu’un pour prendre votre place. Le Swend du lundi 13 octobre à 20h00 · Au Père Lapin est annulé. » ([prénom] = l’autre titulaire) ;
- à chaque remplaçant sélectionné — titre « Le Swend est annulé », message « Tu n’as finalement plus besoin de prendre la place d’Eliot lundi 13 octobre à 20h00 · Au Père Lapin : [autre titulaire] a lui aussi fait appel à quelqu’un pour le remplacer. » (« d’Eliot », « de Kevin » : élision devant une voyelle, un y ou un h, comme dans l’app)

Le prénom du remplaçant de l’autre côté n’est jamais révélé. Aucun rappel n’est envoyé ensuite. L’acceptation qui déclenche cette annulation ne donne pas lieu, en plus, à la push « … a accepté de prendre votre place ».

---

## 10. Téléphone et identité

### 10.1 Identité canonique

L’identité canonique d’un utilisateur Swend est son `profile_id`.

Le numéro de téléphone sert à retrouver / rattacher / inviter une personne.

### 10.2 Normalisation

Les comparaisons de numéros se font sur une forme canonique E.164.

Des formats équivalents doivent être reconnus comme le même numéro, par exemple :

- `06 12 34 56 78`
- `0612345678`
- `+33 6 12 34 56 78`
- `0033 6 12 34 56 78`

### 10.3 Unicité

Deux comptes Swend ne doivent pas pouvoir revendiquer le même numéro canonique.

### 10.4 Rattachements côté serveur

Le client ne doit pas décider lui-même :

- quel `profile_id` correspond à un numéro ;
- quel compte correspond à une personne de confiance ;
- quel destinataire doit être rattaché.

Les rapprochements sensibles sont effectués côté serveur à partir des données canoniques.

### 10.5 Numéro vide ou invalide

Tant que le numéro est vide ou invalide :

- aucun statut `déjà sur Swend` ne doit être affiché ;
- aucune invitation ne doit être proposée comme si la personne était correctement identifiée.

### 10.6 Mobiles en V1

En V1 France, Swend repose sur des numéros mobiles.

Les numéros étrangers sont acceptés avec indicatif international, sans garantie de validation mobile fine pour tous les pays.

### 10.7 Numéro figé en V1

Tant qu’il n’existe pas de vérification SMS/OTP, le numéro associé au compte reste figé après inscription.

Un changement de numéro autonome et vérifié viendra plus tard.

### 10.8 Numéro non vérifié

En V1, le numéro est déclaratif et ne constitue pas encore une preuve forte d’identité.

La vérification SMS/OTP est prévue plus tard, avant une ouverture publique plus large.

### 10.9 Invitations externes

Les canaux V1 sont :

- Messages ;
- WhatsApp.

Le numéro canonique E.164 est utilisé pour construire les liens techniques nécessaires.

`Copier le message` est prévu pour plus tard.

### 10.10 Confidentialité des numéros (D-024)

Un numéro de téléphone n’est jamais accessible simplement parce qu’on peut lire un Swend.

- Une personne de confiance n’obtient jamais le numéro de l’autre titulaire.
- Elle obtient le numéro de son propre titulaire seulement pour l’appeler depuis leur conversation, et seulement tant qu’elle a accès au Swend (règles de §3.6).
- Un titulaire voit les numéros des personnes de confiance qu’il a lui-même ajoutées.
- Le numéro saisi pour l’autre participant sert à le retrouver et à le rattacher ; l’app ne le relit pas.
- Aucun numéro dans les notifications.

Risque résiduel accepté en V1 : un titulaire peut confirmer qu’un numéro qu’il devine est celui de l’autre participant (l’ajout de ce numéro comme personne de confiance est refusé).

---

## 11. Réservation du restaurant

La réservation fait partie de l’expérience Swend, mais son modèle complet n’est pas encore stabilisé.

### 11.1 Informations pratiques

Un Swend contient au minimum :

- une date ;
- une heure ;
- un restaurant.

### 11.2 Confidentialité et remplacement

Le fonctionnement futur de la réservation devra préserver la confidentialité du remplacement.

L’autre titulaire ne doit pas découvrir un remplacement à cause d’un changement de nom, d’une modification visible de réservation ou d’un autre effet secondaire.

### 11.3 Fonctionnement V1 : réservation manuelle

En V1, le Swend est scellé dès que les deux participants se sont mis d’accord et que le destinataire confirme. La réservation du restaurant n’est pas une condition préalable au scellage.

Après le scellage :

- la réservation est gérée manuellement par l’équipe Swend ;
- cette opération est interne et n’ajoute pas de nouvel état visible par l’utilisateur ;
- l’app n’invite jamais l’utilisateur à réserver lui-même (pas de bouton « Réserver la table ») ; seul le lien « Voir le restaurant » reste ;
- il n’y a pas de statut « Réservation en cours » en V1.

Si un Swend est annulé (voir 3.5) :

- l’utilisateur n’a rien à faire vis-à-vis du restaurant ;
- aucun statut de réservation n’est modifié automatiquement ;
- si la table avait déjà été réservée, le suivi interne l’indique comme à annuler auprès du restaurant ; sinon, aucune réservation n’est à effectuer.

Si la réservation ne peut exceptionnellement pas être obtenue :

- l’équipe Swend contacte les participants ;
- elle leur demande d’annuler le Swend ;
- aucun mécanisme automatisé supplémentaire n’est nécessaire en V1.

Ce fonctionnement est acceptable en V1 car les premiers utilisateurs seront principalement des amis et connaissances.

### 11.4 Cible : réservation automatisée, à définir

À terme, Swend doit pouvoir gérer automatiquement la réservation via les restaurants partenaires et/ou leurs plateformes de réservation. Ce fonctionnement futur n’est pas encore défini.

Sont encore ouverts pour ce fonctionnement cible :

- qui réserve ;
- à quel moment ;
- au nom de qui ;
- intégration ou redirection vers un service externe ;
- modification ;
- annulation ;
- interaction entre remplacement et réservation ;
- restaurant complet ;
- empreinte bancaire / frais éventuels ;
- conséquences d’une annulation tardive.

---

## 12. Périmètre V1 et évolutions futures

### 12.1 Cœur V1 retenu

Le cœur de Swend comprend notamment :

- création d’un Swend ;
- invitation de l’autre titulaire ;
- négociation de date limitée à 2 contre-propositions au total ;
- personnes de confiance activées seulement au scellage ;
- réservation du restaurant gérée manuellement par l’équipe Swend après le scellage ;
- acceptation / refus ;
- scellement ;
- personnes de confiance ;
- minimum requis dans les parcours concernés ;
- gestion de la liste ;
- conversations contextuelles ;
- `Un imprévu ?` ;
- demandes simultanées ;
- première acceptation gagnante ;
- refus ;
- désistement ;
- indisponibilité spontanée réversible avant sollicitation ;
- confidentialité stricte entre les deux côtés ;
- double remplacement entraînant l’annulation ;
- invitations Messages / WhatsApp ;
- identité fondée sur `profile_id` avec rapprochement par téléphone canonique ;
- rôles tiers visibles sur leur propre compte ;
- messages non lus persistants ;
- événements système persistants ;
- notifications dans l’app et push pour les actions qui concernent directement un utilisateur ;
- rappels push J-7, J-3, J-1 à 18h et Jour J à H-3 (Europe/Paris), en trois familles (repas, remplacé, cherche) ;
- push immédiate en cas de double remplacement ;
- annulation d’un Swend scellé par l’un de ses titulaires, jusqu’à l’heure du rendez-vous ;
- gel à l’heure du Swend : plus d’imprévu, demandes en attente clôturées, conversations en lecture seule (D-023a) ;
- historique `Mes Swends` : À venir / Passés et annulés.

### 12.2 Prévu plus tard

#### Téléphone

- vérification SMS/OTP ;
- modification autonome et vérifiée du numéro ;
- support international plus complet.

#### Invitations

- `Copier le message`.

#### Réservation

- réservation automatisée via les restaurants partenaires et/ou leurs plateformes de réservation (fonctionnement à définir) ;
- modèle complet ;
- intégrations externes ;
- modification / annulation ;
- éventuels frais.

#### Après le Swend

- chat après le Swend (D-023b, implémenté, voir §3.7) ;
- `Faire un nouveau Swend` depuis la fiche du Swend passé et fermeture du chat (D-023c, implémenté, voir §3.8) ;
- historique détaillé.

#### Recherche / contacts

- recherche avancée de contacts ;
- détection plus automatisée des utilisateurs Swend.

#### UX / finition

- harmonisation complète tutoiement / vouvoiement ;
- empty states ;
- définition finale de tous les compteurs ;
- icônes ;
- spacing ;
- accessibilité ;
- typographie ;
- finitions visuelles.

#### Infrastructure

- staging distant ;
- CI obligatoire ;
- automatisation TestFlight ;
- tests natifs iOS complets.

### 12.3 Évolution des règles

Les règles de ce document ne sont pas immuables.

Lorsqu’une décision produit substantielle change :

1. `PRODUCT_RULES.md` est mis à jour ;
2. la décision est enregistrée dans `DECISIONS.md` ;
3. l’implémentation est adaptée ;
4. les tests QA concernés sont adaptés ;
5. la documentation décrivant l’implémentation est réalignée si nécessaire.

Une ancienne règle ne doit pas rester dans le code ou les tests uniquement parce qu’elle a été vraie auparavant.
