# SWEND — DECISIONS

> **Journal des décisions produit et de travail importantes**
>
> `PRODUCT_RULES.md` décrit **les règles actuellement en vigueur**.
> `DECISIONS.md` conserve la trace des principaux arbitrages qui expliquent comment ces règles ont été choisies ou modifiées.
>
> Une décision peut évoluer. Si elle change, il faut :
> 1. ajouter une nouvelle entrée ici ;
> 2. mettre à jour `PRODUCT_RULES.md` ;
> 3. adapter le code ;
> 4. adapter les tests QA concernés.
>
> Les décisions ci-dessous ont été prises à différents moments du projet puis **revalidées / consolidées le 27/09/2026** lorsqu’une date historique précise n’était pas documentée.

---

## D-001 — Confidentialité absolue du remplacement

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Tant qu’un Swend continue, un titulaire ne doit rien apprendre des démarches de remplacement de l’autre côté.

Cela inclut notamment :
- personnes de confiance ;
- demandes envoyées ;
- refus ;
- acceptations ;
- désistements ;
- conversations ;
- identité du remplaçant.

La confidentialité doit être garantie par le backend / RLS, pas seulement par l’interface.

### Raison
Le mystère est au cœur de la proposition de valeur de Swend. Une simple fuite d’information casse l’expérience.

---

## D-002 — Plusieurs demandes simultanées, première acceptation gagnante

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Un titulaire peut solliciter plusieurs personnes en parallèle.

La première personne qui accepte prend la place. Les autres demandes encore en attente sont clôturées atomiquement.

### Raison
Un imprévu peut arriver tardivement ; attendre une réponse avant de demander à quelqu’un d’autre rendrait le parcours trop fragile.

---

## D-003 — Une acceptation est définitive pour le titulaire initial

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Une fois qu’une personne a accepté de prendre la place d’un titulaire :
- le titulaire initial ne peut pas simplement reprendre sa place ;
- la personne remplaçante prend la place physiquement, mais ne devient pas administratrice du Swend ;
- le titulaire initial reste responsable du Swend jusqu’au jour J.

### Raison
Éviter les revirements et conserver une règle simple : une promesse acceptée doit être fiable.

---

## D-004 — Désistement : réouverture ciblée, jamais automatique

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Si la personne sélectionnée se désiste :
- elle devient indisponible pour ce Swend ;
- les personnes dont la demande avait seulement été clôturée parce qu’une autre avait accepté redeviennent sollicitables ;
- aucune nouvelle demande ne leur est renvoyée automatiquement ;
- les personnes ayant refusé restent indisponibles ;
- les personnes ayant accepté puis s’étant désistées restent indisponibles.

### Raison
Distinguer une indisponibilité réelle d’une simple clôture technique, tout en évitant d’envoyer des demandes sans action explicite du titulaire.

---

## D-005 — Double remplacement : annulation en V1

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Si les deux titulaires ont chacun une personne sélectionnée pour les remplacer, le Swend est annulé.

Les titulaires peuvent connaître la raison générale de l’annulation, sans connaître l’identité des remplaçants.

### Raison
Faire dîner ensemble deux remplaçants qui ne se connaissent pas introduit un autre produit et trop de cas supplémentaires pour la V1.

---

## D-006 — Trois intentions séparées : préparer, discuter, demander

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Les trois actions suivantes restent distinctes :
- `Modifier ma liste` = préparer / gérer ;
- `Discuter` = converser ;
- `Un imprévu ?` = lancer une vraie demande de remplacement.

Une action de gestion ne doit jamais envoyer implicitement une demande.

### Raison
Ces actions correspondent à trois intentions mentales différentes et doivent rester faciles à comprendre.

---

## D-007 — Les conversations restent accessibles après acceptation

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Lorsqu’une personne a accepté de prendre la place du titulaire :
- `Écrire à [Prénom]` reste disponible avec elle ;
- `Discuter` reste disponible avec toutes les autres personnes de confiance ayant Swend.

### Raison
Le titulaire peut vouloir informer, remercier ou continuer à échanger avec le reste de sa liste. Les conversations ne doivent pas disparaître parce qu’une personne a été sélectionnée.

---

## D-008 — Indisponibilité spontanée avant sollicitation

**Statut : Validée**  
**Décidée : 27/09/2026**

### Décision
Une personne simplement prévue peut signaler :

> Je ne serai pas disponible

Elle devient alors indisponible pour ce Swend et le titulaire en est informé.

Tant qu’elle n’a pas refusé une vraie demande, cette indisponibilité est réversible :

> Je suis finalement disponible

### Raison
Éviter que le titulaire pense disposer de solutions qui savent déjà qu’elles ne pourront pas venir, tout en gardant le mécanisme très simple.

---

## D-009 — Une personne sans compte reste une solution réelle

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
En cas d’imprévu, une personne sans compte Swend ne doit pas être masquée.

L’action `Inviter et demander` combine en un seul parcours :
- l’invitation à rejoindre Swend ;
- la vraie demande de prendre la place.

### Raison
Un parcours « inviter → attendre → revenir → demander » serait trop lent, surtout pour un imprévu proche du jour J.

---

## D-010 — Pas de plafond total de 5 personnes de confiance

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Il n’existe pas de plafond produit total à 5 personnes de confiance.

Un écran peut limiter le nombre ajouté en une seule opération, mais l’utilisateur doit pouvoir en ajouter davantage ensuite.

### Raison
La limite historique venait de l’implémentation, pas d’un besoin produit.

---

## D-011 — Négociation de date limitée à 2 contre-propositions au total

**Statut : Validée**  
**Reconfirmée : 27/09/2026**  
**Précisée : 27/09/2026** (formulation initiale : « 2 allers-retours de contre-proposition maximum », jugée ambiguë)

### Décision
Après la proposition initiale, la négociation de date entre les deux titulaires est limitée à **2 contre-propositions au total**, les deux titulaires confondus — et non 2 par personne.

Exemple : Eliot propose A ; David propose B (n°1) ; Eliot propose C (n°2) ; David ne peut plus proposer D. Il peut accepter C, sinon le Swend est annulé.

Sans accord après les 2 contre-propositions autorisées, le Swend est annulé ; il faut créer un nouveau Swend pour recommencer une négociation.

### Raison
Éviter qu’un Swend devienne une conversation de planification interminable. Le produit repose sur un engagement simple et rapide à sceller.

---

## D-012 — Même personne possible des deux côtés, jamais deux places

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
Une même personne peut être prévue comme personne de confiance par les deux titulaires.

Si elle accepte d’un côté :
- elle devient `Indisponible` de l’autre côté ;
- l’autre titulaire ne reçoit aucune explication révélatrice ;
- elle ne peut jamais prendre les deux places.

### Raison
Le cas est plausible dans un cercle d’amis commun, mais il doit préserver la confidentialité et l’unicité de présence.

---

## D-013 — `profile_id` comme identité canonique

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
L’identité canonique d’une personne ayant un compte est son `profile_id`.

Le téléphone normalisé en E.164 sert au rapprochement, à l’invitation et au rattachement provisoire des personnes sans compte.

### Raison
Un numéro de téléphone est une donnée de contact et peut évoluer ; il ne doit pas devenir l’identité métier permanente d’une personne.

---

## D-014 — OTP différé, numéro figé en attendant

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
En V1, le numéro est déclaratif et n’est pas encore vérifié par SMS/OTP.

En attendant la vérification :
- le numéro associé au compte reste figé ;
- le changement autonome et vérifié du numéro est reporté ;
- l’OTP doit être mis en place avant une ouverture publique plus large.

### Raison
Éviter qu’un utilisateur puisse librement revendiquer le numéro d’une autre personne avant l’existence d’un mécanisme de preuve de possession.

---

## D-015 — Push pour les actions qui concernent directement quelqu’un

**Statut : Validée**  
**Décidée : 27/09/2026**

### Décision
Lorsqu’une action concerne directement un autre utilisateur, celui-ci doit être informé :
- dans l’application ;
- par notification push.

Exemples :
- Swend reçu ;
- nouvelle étape de négociation ;
- nouveau message ;
- demande de remplacement ;
- demande annulée ;
- acceptation ;
- refus ;
- désistement ;
- clôture automatique ;
- annulation pour double remplacement.

Les rappels automatiques liés au temps (J-7, J-3, J-1, Jour J) restent un chantier séparé.

### Raison
Une action qui attend ou modifie directement quelque chose pour un utilisateur ne doit pas dépendre du fait qu’il pense à rouvrir l’app.

---

## D-016 — Réservation : ne pas figer trop tôt le modèle

**Statut : Validée**  
**Consolidée : 27/09/2026**

### Décision
La réservation fait partie de l’expérience Swend, mais son modèle détaillé reste volontairement ouvert.

Ne pas figer encore :
- qui réserve ;
- quand ;
- au nom de qui ;
- intégration externe ;
- modification / annulation ;
- frais éventuels.

Toute future solution doit préserver la confidentialité du remplacement.

### Raison
Ces choix dépendent fortement du futur modèle restaurant / réservation et ne doivent pas bloquer le cœur social de la V1.

---

## D-017 — Banc QA permanent comme protection contre les régressions

**Statut : Validée et implémentée**  
**Décidée / mise en place : 27/09/2026**

### Décision
Swend utilise désormais un banc QA local permanent avec trois niveaux :
- tests métier rapides ;
- smoke E2E ;
- full regression E2E.

Le QA doit rester isolé de la production et refuser de démarrer contre l’environnement de production.

Pour un lot important, la full regression doit être exécutée avant livraison.

### État au 27/09/2026
- tests métier : **261 PASS / 0 FAIL** ;
- E2E full : **353 PASS / 0 FAIL** ;
- scénarios E2E : **16 / 16** ;
- résultat global : **PASS**.

### Raison
Réduire fortement les tests manuels répétitifs et rendre les régressions métier / confidentialité détectables automatiquement.

---

## D-018 — Séparer règle produit et état d’implémentation

**Statut : Validée**  
**Décidée : 27/09/2026**

### Décision
Les documents ont des rôles distincts :

- `PRODUCT_RULES.md` = **ce que le produit doit faire** ;
- `SWEND_README.md` = **ce qui est principalement implémenté aujourd’hui / guide d’onboarding** ;
- `ARCHITECTURE.md` = **architecture technique** ;
- `qa/README.md` = **fonctionnement du banc QA** ;
- `DECISIONS.md` = **historique des arbitrages importants**.

En cas d’écart entre comportement attendu et implémentation, `PRODUCT_RULES.md` fait foi pour la décision produit.

### Raison
Éviter qu’un comportement existant dans le code soit interprété comme une décision produit simplement parce qu’il existe déjà.

---

## D-019 — Personnes de confiance activées seulement après scellage

**Statut : Validée**  
**Décidée : 27/09/2026**

### Décision
Une personne de confiance peut être choisie pendant la création du Swend, mais elle n’est activée qu’une fois le Swend scellé.

Avant le scellage : aucune notification automatique, rien dans « On compte sur toi », aucun accès au Swend, aucune conversation de son côté.

Si le Swend est refusé, annulé avant scellage ou si la négociation n’aboutit jamais, elle n’est jamais informée automatiquement et ne voit jamais ce Swend.

Un partage manuel (Messages / WhatsApp) choisi volontairement par l’utilisateur n’est pas concerné.

### Raison
Tant que l’autre titulaire n’a pas accepté, il n’y a pas de rendez-vous : solliciter l’attention d’une personne de confiance pour un Swend qui n’existera peut-être jamais est prématuré.

---

## D-020 — Réservation manuelle en V1

**Statut : Validée**  
**Décidée : 27/09/2026**

### Décision
En V1, le Swend est scellé dès que les deux participants se sont mis d’accord et que le destinataire confirme. La réservation du restaurant n’est pas une condition préalable au scellage.

Après le scellage :
- la réservation est gérée manuellement par l’équipe Swend ;
- cette opération est interne et n’ajoute pas de nouvel état visible par l’utilisateur ;
- il n’y a pas de statut « Réservation en cours » en V1.

Si la réservation ne peut exceptionnellement pas être obtenue :
- l’équipe Swend contacte les participants ;
- elle leur demande d’annuler le Swend ;
- aucun mécanisme automatisé supplémentaire n’est nécessaire en V1.

### Contexte
Les premiers utilisateurs seront principalement des amis et connaissances, ce qui rend ce fonctionnement acceptable pour la V1.

### Vision cible
À terme, Swend doit pouvoir gérer automatiquement la réservation via les restaurants partenaires et/ou leurs plateformes de réservation. Ce fonctionnement futur n’est pas encore défini.

### Précise
D-016 (pour la V1 ; le modèle cible reste ouvert).

---

## D-021 — Rappels automatiques autour du Jour J et push de double remplacement

**Statut : Validée**  
**Décidée : 27/09/2026**

### Décision
Rappels push automatiques pour les Swends scellés : J-7, J-3 et J-1 à 18h, et Jour J 3 heures avant le rendez-vous, en Europe/Paris pour la V1.

- Push uniquement, sans box supplémentaire dans l’app ; toujours la date, l’heure et le restaurant.
- Trois familles, selon l’état de chaque côté au moment de l’envoi : « repas » (personne qui vient réellement, avec l’autre titulaire officiel), « remplacé » (titulaire dont quelqu’un a accepté de prendre la place : « Kevin prend ta place »), « cherche » (titulaire sans remplaçant accepté ayant au moins une demande en attente, refusée ou désistée ; annuler toutes ses demandes en attente sans refus ni désistement le ramène à l’état normal).
- L’autre titulaire voit toujours le titulaire officiel : aucun remplacement ne fuit par les rappels.
- Destinataires et famille recalculés à chaque envoi ; pas de rattrapage ; une échéance au plus une fois par personne et par Swend (garanti par le backend).
- Aucun rappel pour un Swend non scellé ou inactif.
- Double remplacement : push immédiate aux deux titulaires et aux deux remplaçants sélectionnés (textes validés), sans révéler le remplaçant du côté opposé ; elle remplace la push d’acceptation qui l’a déclenchée ; plus aucun rappel ensuite.
- Au clic, la destination est recalculée selon l’état actuel (fiche du Swend, fiche de remplaçant, ou « Un imprévu ? »).

Textes détaillés : `PRODUCT_RULES.md` §9.7 et §9.8.

### Raison
Rappeler le rendez-vous sans jamais trahir le mystère, et pousser un titulaire qui cherche encore quelqu’un à agir tant qu’il en est temps.

### Précise
D-015 (rappels distincts des notifications d’actions directes) et D-005 (double remplacement).

---

## Ajouter une décision

Créer une nouvelle entrée avec :

```md
## D-XXX — Titre court

**Statut : À décider / Validée / Remplacée**  
**Date : JJ/MM/AAAA**

### Décision
...

### Raison
...

### Remplace éventuellement
D-XXX
```

Ne pas modifier silencieusement une ancienne décision importante : ajouter une nouvelle entrée qui la remplace ou la précise.
