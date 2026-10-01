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

## D-022 — Annulation manuelle d’un Swend scellé

**Statut : Validée**  
**Décidée : 28/09/2026**

### Décision
Seuls les deux titulaires originaux peuvent annuler un Swend scellé, jusqu’à l’heure prévue du rendez-vous (`date_retenue`). Un remplaçant ne peut jamais annuler. Un titulaire peut annuler même si quelqu’un a déjà accepté de prendre sa place.

- Confirmation selon l’état du côté de celui qui annule :
  - aucun imprévu lancé : proposer d’abord « Trouver quelqu’un pour me remplacer », puis « Annuler malgré tout » ;
  - en recherche (état D-021 « cherche ») : pas de nouveau parcours d’imprévu ; texte selon qu’il reste ou non des demandes en attente ; « Continuer à chercher » ;
  - quelqu’un a accepté : le prénom de cette personne, « le Swend prendra fin pour tout le monde ».
- Effet immédiat et atomique : le Swend est annulé, toutes les demandes encore en attente sont clôturées. Aucun motif demandé ni transmis.
- Swend enregistre qui a annulé et quand (`annule_par`, `annule_le`), sans l’afficher, pour pouvoir l’exploiter plus tard (indicateurs du profil, lot dédié). Aucune attribution rétroactive : pour les annulations antérieures, l’information reste inconnue.
- Push à l’autre titulaire ; au remplaçant accepté, qui apprend quel titulaire a annulé ; aux personnes dont la demande était en attente (sans détail). Rien pour une personne seulement prévue. L’identité d’un remplaçant n’est jamais révélée à l’autre titulaire.
- Les conversations existantes (titulaire ↔ personnes de confiance) restent accessibles ; pas de nouveau chat entre titulaires.
- Réservation : pour l’utilisateur, l’annulation est gérée par Swend ; on ne lui demande jamais de prévenir le restaurant. Logique D-020 inchangée (rien d’automatique ; à annuler au restaurant seulement si la table avait été réservée).
- Historique : un Swend annulé ne disparaît pas ; « Mes Swends » sépare « À venir » et « Passés et annulés » ; carte grisée « Annulé ». Il reste visible pour les titulaires et le remplaçant qui avait accepté, pas pour les personnes seulement prévues, sollicitées ou ayant refusé.
- Un Swend scellé (actif, passé ou annulé) ne peut plus être supprimé par un utilisateur ; un Swend jamais scellé reste supprimable. La suppression interne (équipe, banc QA) reste possible.
- Les alertes internes par e-mail (scellage, annulation) sont prévues plus tard.

Textes détaillés : `PRODUCT_RULES.md` §3.5.

### Raison
Laisser un titulaire mettre fin proprement à un Swend, en l’orientant d’abord vers un remplaçant, sans jamais trahir un remplacement ni lui faire gérer la réservation.

### Précise
§4.4 (un remplaçant n’annule pas), D-020 (réservation manuelle), D-021 (état « cherche », rappels : aucun rappel pour un Swend annulé).

---

## D-023a — Gel à l’heure du Swend

**Statut : Validée**  
**Décidée : 29/09/2026**

### Décision
À l’heure prévue du Swend (`date_retenue`, heure du serveur, jamais l’horloge du client), l’état du rendez-vous est figé : on ne gère plus l’imprévu, on entre dans l’après-Swend.

- Plus aucune action d’imprévu : demande, annulation de demande, acceptation / refus, désistement, ajout et demande, (in)disponibilité, ajout ou retrait d’une personne de confiance ; annulation du Swend déjà impossible (D-022). Refus serveur `swend_passe` ; l’app masque ces actions et affiche un message propre si le serveur refuse.
- Demandes encore en attente clôturées automatiquement à H (moteur planifié, idempotent, sans doublon) ; push « La demande n’est plus d’actualité / L’heure du Swend est passée. » à la personne sollicitée, une seule par personne ; rien de spécifique pour le titulaire qui cherchait ; aucune push parasite.
- Conversations de l’imprévu en lecture seule dès H (historique conservé) ; événement de fin « Le Swend a commencé. Cette conversation est désormais terminée. » seulement dans les conversations ayant eu une activité, jamais « non lu ».
- **Nouvelle règle** : dès qu’un Swend est annulé, ses conversations d’imprévu passent immédiatement en lecture seule (compatible avec D-022 : elles restent lisibles).
- Le statut reste `confirme` en base ; « passé » est dérivé de la date ; aucun badge (`Réalisé`, `Terminé`…) ; aucun indicateur du profil modifié.
- Historique : titulaires et remplaçant sélectionné gardent le Swend ; les personnes seulement prévues, sollicitées, ayant refusé ou désistées ne le voient plus comme élément actif ou historique.
- Invariants : jamais de scellement d’un Swend dont la date est passée ; date d’un Swend scellé non modifiable par l’app ; retirer une personne ne détruit plus sa conversation (fiche archivée) ; un ancien rappel cliqué après H n’ouvre plus « Un imprévu ? ».
- Rattrapage : les Swends déjà passés à la mise en place sont considérés comme traités (aucune push, aucun événement rétroactif).

- Accès (précisé le 30/09) : une fois le Swend passé ou annulé, seuls les deux titulaires (toutes les conversations actives de leur côté) et le remplaçant effectivement sélectionné (sa conversation) gardent l’accès ; les personnes seulement prévues, sollicitées, ayant refusé ou désistées le perdent, données conservées ; une personne retirée n’a plus accès ; avant H, chaque personne de confiance non retirée garde les accès de son rôle. Garanti par des fonctions et politiques RLS versionnées ; `est_remplacant_du_pacte()` (non versionnée en production) n’est pas modifiée. Même règle pour le numéro du titulaire : nouvelle fonction versionnée, l’ancienne `telephone_titulaire_du_pacte()` n’est plus exécutable par l’app (non réécrite).

D-023b (chat après le Swend) est décrit ci-dessous ; D-023c (« Faire un nouveau Swend ») est décidé à part et **non implémenté**.

Textes détaillés : `PRODUCT_RULES.md` §3.6.

### Raison
Socle de l’après-Swend : l’existant laissait presque toutes les actions d’imprévu possibles après l’heure du rendez-vous. Un rendez-vous commencé ne doit plus pouvoir changer, et chacun doit savoir que la conversation d’imprévu est terminée.

### Précise
D-022 (annulation jusqu’à l’heure du rendez-vous ; conversations d’un Swend annulé désormais en lecture seule), D-021 (clic sur un rappel), D-003 et D-004 (plus d’acceptation ni de désistement après H).

### Mise en production
Techniquement en production depuis le 30/09/2026 : migration `20260929000000_gel_a_h.sql` exécutée (10/10 vérifications, contrôle `gel_a_h_controle.sql` 7/7), app déployée, planification pg_cron `swend-gel-a-h` active (toutes les 5 minutes, premières exécutions `succeeded`). Test réel humain à faire. D-023b et D-023c ne sont pas implémentées.

---

## D-024 — Confidentialité des numéros de téléphone

**Statut : Validée**  
**Décidée : 30/09/2026**

### Décision
Un numéro de téléphone n’est jamais accessible simplement parce qu’un utilisateur peut lire un Swend.

- Une personne de confiance n’obtient jamais le numéro de l’autre titulaire.
- Le numéro de son propre titulaire ne lui parvient que par `telephone_titulaire_accessible()`, selon ses droits du moment (D-023a).
- La ligne `pactes` ne donne plus aucun numéro à l’app : `destinataire_telephone` reste écrit à la création (rattachement du destinataire par la base) mais n’est plus relu, ni par les personnes de confiance ni par les titulaires (aucun écran ne l’utilisait). `destinataire_telephone_e164` reste illisible.
- Aucun numéro dans les notifications ni dans les journaux de l’app (le log d’ouverture d’une notification ne contient plus que son type).
- Règles entre les deux titulaires inchangées en pratique : l’initiateur ne revoyait déjà ce numéro nulle part, le destinataire n’a jamais obtenu celui de l’initiateur.

Correction minimale : l’app ne demande plus la colonne ; une migration courte retire le `SELECT` de l’app sur `pactes.destinataire_telephone` (et réaffirme l’absence de `SELECT` sur `destinataire_telephone_e164`), garde l’écriture à la création ; aucune politique RLS ni fonction modifiée.

Ordre de production obligatoire : tests, déploiement de l’app, vérification de la nouvelle app en production, puis seulement la migration.

### Risques résiduels acceptés (V1)
- Un titulaire peut confirmer qu’un numéro qu’il devine est celui de l’autre titulaire : l’ajout de ce numéro comme personne de confiance est refusé (`personne_est_participant`). Confirmation d’une hypothèse seulement ; accepté pour la V1.
- Hors D-024 : nettoyage des tables internes `sauvegarde.*` (fermées à l’app) ; commentaire obsolète de `notifier_nouveau_message()` (non versionnée) qui mentionne encore `telephone_titulaire_du_pacte()` — signalé, fonction non réécrite pour cela.

### Raison
Audit du 30/09 : toute personne de confiance ayant accès à un Swend lisait `pactes.destinataire_telephone`, donc le numéro de l’autre titulaire côté initiateur, et celui de son titulaire sans passer par la fonction dédiée côté destinataire. L’app le téléchargeait à chaque chargement de l’accueil, sans l’afficher.

### Précise
D-001 (confidentialité du remplacement), D-023a (numéro du titulaire soumis à la règle d’accès).

### Mise en production
QA OK (métier 776/0, E2E 598/0). App déployée le 30/09/2026 (gh-pages `80b4739`, source `07e1fa2`) : elle ne relit plus le numéro. Migration `20260930000000_confidentialite_telephones.sql` exécutée en production le 30/09/2026 après vérification de l’app (6/6 vérifications à true). D-024 techniquement en production ; test réel humain à faire.

---

## D-023b — Chat après le Swend

**Statut : Validée**  
**Décidée : 30/09/2026**

### Décision
Après un Swend qui a eu lieu, le silence est levé : un chat s’ouvre automatiquement entre les deux titulaires d’origine et, s’il existe, le remplaçant sélectionné à l’heure du Swend (3 personnes au plus). Détails : `PRODUCT_RULES.md` §3.7.

- Ouverture : H+3 si H+3 ≤ 23:00 (Europe/Paris) le jour du Swend, sinon 10:00 le lendemain ; calcul serveur, changements d’heure compris. Seulement pour un Swend `confirme`, scellé et figé par D-023a ; jamais annulé, double remplacement, `maintenu`.
- Pas de rattrapage : borne de mise en service explicite (`chat_apres_swend_service`), repositionnée à `now()` par le fichier de planification dans la même exécution que l’activation du job `swend-chat-apres` : aucun Swend dont l’ouverture précède l’activation réelle ne reçoit de chat.
- Moteur `ouvrir_chats_apres_swend()` chaque minute (pg_cron) ; chat, participants et état visibles dans une seule transaction ; push « Alors, ce Swend ? » seulement si le retard est ≤ 12 h (la livraison FCM n’est pas nécessaire à l’ouverture).
- Participants figés à l’ouverture (prénom du compte) ; plus d’un remplaçant actif : chat non ouvert, anomalie enregistrée.
- Révélation seulement à partir de l’ouverture ; tutoiement conservé pour le remplaçant.
- Accueil : carte persistante « Alors, ce Swend ? » jusqu’à la première ouverture, puis non-lus (2 cartes au plus) ; priorité : urgences des Swends en cours, puis après le Swend, puis prochain Swend.
- Messages : texte et emoji, 2 000 caractères ; une push par message aux autres participants, sans contenu ni numéro ; lecture individuelle ; clic → chat (mobile et web, Edge Function `lienWeb()`).
- Séparation technique complète avec les conversations d’imprévu (aucune table ni fonction partagée) ; accès uniquement par la liste des participants ; l’app n’écrit que par des fonctions serveur.
- Préparé pour D-023c (non implémenté) : `ferme_le`, `motif_fermeture`, messages système, lecture seule.

### Raison
Un Swend réellement vécu mérite un débrief ; le mystère du remplacement n’a plus de raison d’être une fois le rendez-vous passé.

### Précise
D-023a (Swend figé à H), D-001 (confidentialité jusqu’à l’ouverture), D-024 (aucun numéro).

### Mise en production
Migration `20260930010000_chat_apres_swend.sql` exécutée en production le 30/09/2026 (6/6 vérifications). App déployée le 30/09/2026 (gh-pages `7834b5f`). Edge Function `send-notification` déployée (lien web `?chat_apres=`). Planification `swend-chat-apres` active depuis le 30/09/2026 (chaque minute ; borne de mise en service repositionnée à l’activation ; premières exécutions `succeeded` à 13:49, 13:50, 13:51 UTC). D-023b techniquement en production ; test réel humain à faire. D-023c non commencé.

---

## D-025 — Délai minimum de 15 jours avant un Swend

**Statut : Validée**  
**Décidée : 01/10/2026**

### Décision
Pour un Swend créé par un utilisateur standard, aucune date ne peut tomber avant le jour de création (heure de Paris) + 15 jours. Exemple : créé le 1er octobre → première date possible le 16 octobre, à toute heure. Détails : `PRODUCT_RULES.md` §3.2.

- S’applique aux dates proposées à la création, aux contre-propositions et à la date retenue.
- Calcul exclusivement serveur : `pactes.date_minimale` (date) est posée par la base à la création, jamais par l’app ni modifiable par elle. Toute valeur envoyée par l’app est ignorée.
- Comptes fondateurs (`kevinarner@hotmail.com`, `eliotschlang@gmail.com`, `eliotschlang@icloud.com`) : exemptés. Reconnus par l’email **confirmé** de leur compte Supabase Auth, jamais par `profiles.email` ni par une valeur de l’app. Table interne `comptes_fondateurs`, illisible par l’app.
- L’exemption suit le Swend : un Swend créé par un fondateur est exempté pour toute sa négociation (contre-propositions de l’autre titulaire comprises) ; un Swend créé par un utilisateur standard garde sa limite, même si le destinataire est fondateur.
- Pas de rétroactivité : les Swends existants gardent `date_minimale = null` (pas de limite).
- L’app n’utilise la date que pour le calendrier (rien avant la première date possible) et pour le message de refus : « Choisissez une date au moins 15 jours à l’avance. Première date possible : 16 octobre. » (date donnée par la base dans le refus `date_trop_proche`).
- La fonction utilisée par l’app, `date_minimale_nouveau_swend()`, n’a aucun paramètre : elle s’appuie sur `auth.uid()` (impossible de tester l’exemption d’un autre compte) et ne renvoie qu’une date ou null.
- Aucune autre règle modifiée (2 contre-propositions au plus, jours, créneaux, statuts).

### Hors D-025
- D-025b (petit lot à venir) : la date retenue doit être l’une des dates proposées. Aujourd’hui, D-025 ne contrôle que le délai de 15 jours pour la date retenue.

### Raison
Laisser le temps d’organiser le Swend (réservation manuelle, personnes de confiance) ; les fondateurs gardent la souplesse nécessaire aux tests et aux démonstrations.

### Précise
D-011 (négociation de date), D-020 (réservation manuelle), D-024 (lecture colonne par colonne de `pactes`).

### Mise en production
QA OK le 01/10 (métier 895/0, E2E 677/0, 28/28 scénarios). Préparée, **non exécutée**. Ordre : vérification (lecture seule) des 3 comptes fondateurs dans `auth.users`, puis migration `20261001000000_delai_minimum_swend.sql` (5 vérifications), puis déploiement de l’app (qui lit `date_minimale` : elle ne doit pas précéder la migration).

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
