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

### 3.3 Scellement

Une fois l’accord des deux titulaires obtenu, le Swend devient **Scellé**.

À partir de là, le rendez-vous n’est plus normalement rediscuté entre eux avant le jour J.

En V1, la réservation du restaurant n’est pas une condition préalable au scellage : le Swend est scellé dès que les deux participants se sont mis d’accord et que le destinataire confirme (voir 11.3).

### 3.4 Refus

Le destinataire peut refuser le Swend. Le Swend est alors annulé.

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
- retirer une personne lorsque l’état le permet ;
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
- clôture automatique.

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
- annulation liée au double remplacement.

Les textes exacts, regroupements éventuels et priorités de push peuvent être affinés ultérieurement.

### 9.7 Rappels automatiques

Les rappels automatiques liés au temps — par exemple J-7, J-3, J-1, Jour J — restent à définir plus tard.

Ils sont distincts des notifications déclenchées par une action directe d’un utilisateur.

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
- il n’y a pas de statut « Réservation en cours » en V1.

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
- notifications dans l’app et push pour les actions qui concernent directement un utilisateur.

### 12.2 Prévu plus tard

#### Téléphone

- vérification SMS/OTP ;
- modification autonome et vérifiée du numéro ;
- support international plus complet.

#### Invitations

- `Copier le message`.

#### Notifications automatiques

- J-7 ;
- J-3 ;
- J-1 ;
- Jour J ;
- fréquence et contenu exacts.

#### Réservation

- réservation automatisée via les restaurants partenaires et/ou leurs plateformes de réservation (fonctionnement à définir) ;
- modèle complet ;
- intégrations externes ;
- modification / annulation ;
- éventuels frais.

#### Après le Swend

- historique détaillé ;
- `Refaire un Swend`.

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
