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

**Statut : Remplacée par D-027 (12/10/2026)**  
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

**Statut : Validée — précisée par D-027 pour l’imprévu (12/10/2026)**  
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

**Statut : Validée — révisée par D-027 (12/10/2026), mise en œuvre au lot 2**  
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
- Demandes encore en attente clôturées automatiquement à H (moteur planifié, idempotent, sans doublon) — *révisé par D-027 le 20/10 : une demande encore en attente à H signifie une recherche non résolue à H-3 ; le gel applique d’abord l’échéance et annule le Swend (voir D-027, « Choix techniques (échéance H-3 ferme) »)* ; push « La demande n’est plus d’actualité / L’heure du Swend est passée. » à la personne sollicitée, une seule par personne ; rien de spécifique pour le titulaire qui cherchait ; aucune push parasite.
- Conversations de l’imprévu en lecture seule dès H (historique conservé) ; événement de fin « Le Swend a commencé. Cette conversation est désormais terminée. » seulement dans les conversations ayant eu une activité, jamais « non lu ».
- **Nouvelle règle** : dès qu’un Swend est annulé, ses conversations d’imprévu passent immédiatement en lecture seule (compatible avec D-022 : elles restent lisibles).
- Le statut reste `confirme` en base ; « passé » est dérivé de la date ; aucun badge (`Réalisé`, `Terminé`…) ; aucun indicateur du profil modifié.
- Historique : titulaires et remplaçant sélectionné gardent le Swend ; les personnes seulement prévues, sollicitées, ayant refusé ou désistées ne le voient plus comme élément actif ou historique.
- Invariants : jamais de scellement d’un Swend dont la date est passée ; date d’un Swend scellé non modifiable par l’app ; retirer une personne ne détruit plus sa conversation (fiche archivée) ; un ancien rappel cliqué après H n’ouvre plus « Un imprévu ? ».
- Rattrapage : les Swends déjà passés à la mise en place sont considérés comme traités (aucune push, aucun événement rétroactif).

- Accès (précisé le 30/09) : une fois le Swend passé ou annulé, seuls les deux titulaires (toutes les conversations actives de leur côté) et le remplaçant effectivement sélectionné (sa conversation) gardent l’accès ; les personnes seulement prévues, sollicitées, ayant refusé ou désistées le perdent, données conservées ; une personne retirée n’a plus accès ; avant H, chaque personne de confiance non retirée garde les accès de son rôle. Garanti par des fonctions et politiques RLS versionnées ; `est_remplacant_du_pacte()` (non versionnée en production) n’est pas modifiée. Même règle pour le numéro du titulaire : nouvelle fonction versionnée, l’ancienne `telephone_titulaire_du_pacte()` n’est plus exécutable par l’app (non réécrite).

D-023b (chat après le Swend) et D-023c (« Faire un nouveau Swend », fermeture du chat) sont décrits ci-dessous.

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

**Statut : Validée — complétée par D-027 (chat d’annulation, lot 2)**  
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
- Préparé pour D-023c (utilisé par D-023c, voir plus bas) : `ferme_le`, `motif_fermeture`, messages système, lecture seule.

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
- Comptes fondateurs (3 adresses : celle de Kevin et les 2 d’Eliot ; enregistrées en production, retirées du dépôt public) : exemptés. Reconnus par l’email **confirmé** de leur compte Supabase Auth, jamais par `profiles.email` ni par une valeur de l’app. Table interne `comptes_fondateurs`, illisible par l’app.
- L’exemption suit le Swend : un Swend créé par un fondateur est exempté pour toute sa négociation (contre-propositions de l’autre titulaire comprises) ; un Swend créé par un utilisateur standard garde sa limite, même si le destinataire est fondateur.
- Pas de rétroactivité : les Swends existants gardent `date_minimale = null` (pas de limite).
- L’app n’utilise la date que pour le calendrier (rien avant la première date possible) et pour le message de refus : « Choisissez une date au moins 15 jours à l’avance. Première date possible : 16 octobre. » (date donnée par la base dans le refus `date_trop_proche`).
- La fonction utilisée par l’app, `date_minimale_nouveau_swend()`, n’a aucun paramètre : elle s’appuie sur `auth.uid()` (impossible de tester l’exemption d’un autre compte) et ne renvoie qu’une date ou null.
- Aucune autre règle modifiée (2 contre-propositions au plus, jours, créneaux, statuts).

### Écart connu, accepté (01/10)
Seuls lundi, mardi et mercredi sont sélectionnables (règle inchangée) : J+15 peut tomber un autre jour, le premier jour cliquable est alors le lundi suivant, alors que le message de refus annonce J+15. Le calendrier empêche déjà ce cas en pratique ; D-025 n’est pas rouvert pour cela.

### Hors D-025
- D-025b : la date retenue doit être l’une des dates proposées. Garanti par la base pour toute écriture depuis R2 (paquet `R2-01`, en production depuis le 03/10, voir « Mise en production »).

### Raison
Laisser le temps d’organiser le Swend (réservation manuelle, personnes de confiance) ; les fondateurs gardent la souplesse nécessaire aux tests et aux démonstrations.

### Précise
D-011 (négociation de date), D-020 (réservation manuelle), D-024 (lecture colonne par colonne de `pactes`).

### Mise en production
QA OK le 01/10 (métier 895/0, E2E 677/0, 28/28 scénarios). Migration `20261001000000_delai_minimum_swend.sql` exécutée en production le 01/10/2026 (5/5 vérifications à true), puis app déployée le 01/10/2026 (gh-pages `34629e7`, source `79e542e`) — ordre respecté : l’app lit `date_minimale`, elle ne pouvait pas précéder la migration. Contrôle en lecture seule des 3 comptes fondateurs dans `auth.users` : 1 compte chacun, email confirmé — exemptions effectives. D-025 techniquement en production ; test réel humain à faire.

Complément du 03/10, **R2** (convention temporelle : heure de Paris, instants absolus, dates proposées avec fuseau explicite ; D-025 corrigé et réactivé ; D-025b) : **déployé et vérifié techniquement**. App publiée le 03/10 (gh-pages `3663f46`, source `c897f19`), puis paquet `R2-01` (niveau 2, empreinte `1b8c2366d48e`, Go d’Eliot du 03/10) appliqué le 03/10 à 14:21 UTC : `sauvegarde`, `appliquer` et `verifier` HTTP 201, `RESULTAT: SUCCES` (reçu `supabase/changements/R2-01/journal/20261003T142147Z-appliquer.log`, commit `6bbab7f`, branche `recu/R2-01`). `verifier.sql` conforme au résumé attendu du paquet : rendez-vous 17/11 19:00 à Paris, push « mardi 17 novembre à 19h00 », rappels J-7 / J-1 / jour J, chat 22:00, déclencheur D-025 `O` (il avait été constaté désactivé le 03/10), `date_minimale` 2026-10-17 pour `6cb94c32`. Déclencheur `trg_verrou_zz_dates_swend` encore actif au contrôle en lecture seule du 15/10 (préconditions de `D-027-01`). Limites : les contrôles « session de travail » prévus par le paquet ne sont pas tracés (catalogue ; instantanés de parité QA `qa/db/parite/*_production.tsv` et `declencheurs_admis.tsv`, qui montrent encore le déclencheur D-025 `D` en production) ; jobs pg_cron `succeeded` au 15/10. Test réel humain à faire (D-025 et D-025b).

---

## D-023c — Faire un nouveau Swend, fermeture du chat après le Swend

**Statut : Validée**  
**Décidée : 03/10/2026**

### Décision
Un nouveau Swend scellé entre deux personnes ferme le chat après le Swend où elles se parlent ensemble : le silence revient jusqu’au nouveau rendez-vous. Détails : `PRODUCT_RULES.md` §3.8.

- Fermeture définitive au **scellement** seulement, décidée par la base (déclencheur sur `pactes`), quel que soit le point d’entrée ; une invitation ou une négociation ne ferme rien. Concerne tout chat déjà ouvert où les deux personnes du nouveau Swend participent ensemble (titulaires, remplaçant, chat à 2 ou à 3) ; pas un chat où une seule participe.
- Chat fermé : `ferme_le`, `motif_fermeture = 'nouveau_swend'`, lecture seule, historique conservé ; un seul message système (« Un nouveau Swend a été scellé. / Ce chat est désormais fermé pour préserver le silence. »), daté de la fermeture, jamais un second (autre paire, scellements concurrents) ; aucune push.
- Jamais de réouverture : l’annulation du nouveau Swend, même immédiate, ne change rien et n’ajoute aucun message. Négociations parallèles : non annulées, le premier scellement ferme.
- Chat pas encore ouvert : si le nouveau Swend est scellé avant l’heure d’ouverture du chat d’un Swend précédent dont les deux sont participants potentiels, ce chat ne s’ouvre jamais (aucun faux chat fermé, aucun message, aucun accès). Participants potentiels : une seule fonction, partagée par le moteur d’ouverture et la fermeture (deux titulaires + remplaçant sélectionné).
- `Faire un nouveau Swend` sur la fiche du Swend passé (sous `Discuter`, chat ouvert seulement) : à 2, directement `Quand et où ?` ; à 3, choix entre les deux autres personnes (même niveau, sans rôle, sans recherche ni `Continuer`). Personne désignée par son identité serveur, jamais par un numéro (D-024) ; tout repart de zéro (date, restaurant, personnes de confiance).
- Un seul Swend en cours par paire, règle globale garantie par la base quel que soit le point d’entrée (`Faire un nouveau Swend`, `Créer un Swend` depuis l’accueil) : `Un Swend est déjà en cours entre vous.` (à 2, et depuis l’accueil) ; carte désactivée `Tu as déjà un Swend en cours avec Kevin.` (à 3).
- Après fermeture : `Voir la conversation`, `Conversation fermée`, plus de création ; pas de statut lourd dans Mes Swends. Textes nouveaux au tutoiement.

### Choix techniques (03/10)
- « Swend en cours » entre deux personnes : un Swend dont elles sont les deux titulaires, en négociation avec au moins une date proposée à venir, ou scellé (`confirme`) et pas encore passé. Une invitation dont toutes les dates sont passées ne bloque pas.
- « Swend précédent » (chat pas encore ouvert) : un Swend scellé dont la date est antérieure à celle du nouveau Swend. Un Swend scellé plus tardif que le nouveau garde son chat.
- Création depuis le chat : fonction serveur `creer_swend_depuis_chat()` (numéro du profil recopié par la base, jamais renvoyé ; D-025 appliqué ; personnes de confiance dans la même transaction, tout ou rien) ; `options_nouveau_swend()` pour l’écran (prénom, identifiant de participant, Swend en cours).
- Règle « un Swend en cours par paire » (précisée le 03/10 : globale) : déclencheur `trg_verrou_un_swend_par_paire` sur toute création au nom d’un utilisateur (app : accueil et chat), refus `swend_deja_en_cours`, verrou par paire contre les créations simultanées ; destinataire sans compte reconnu par son numéro canonique. Les écritures de service (SQL Editor, moteurs) ne sont pas concernées. Définition unique de « en cours » : `swend_en_cours()`.

### Écarts signalés (03/10)
- Textes anciens au vouvoiement, non modifiés (D-023c ne réécrit pas l’existant) : push « Alors, ce Swend ? / Le silence est levé. Vous pouvez maintenant en reparler dans le chat. », « [Prénom] vous a écrit », état vide « À vous de débriefer. », révélation « Kevin a pris votre place. », « Réessayez », message D-025 « Choisissez une date… », entre autres.

### Raison
Préserver le principe du silence avant un Swend : deux personnes qui ont scellé un nouveau rendez-vous ne doivent plus pouvoir se parler dans l’ancien chat, et la reprise d’un Swend avec quelqu’un rencontré doit être simple et sans numéro.

### Précise
D-023b (chat après le Swend), D-024 (aucun numéro), D-025 (délai minimum), D-019 (scellement).

### Mise en production
**Déployé le 04/10 ; vérification technique partielle.** Paquet `D-023c-01` (niveau 1, empreinte `3d84fe115285`, Go d’Eliot du 04/10) exécuté le 04/10 à 06:42 UTC : `appliquer` HTTP 201 ; `verifier` HTTP 400 (`permission denied for function swend_en_cours`), d’où `RESULTAT: ECHEC` (reçu `supabase/changements/D-023c-01/journal/20261004T064215Z-appliquer.log`, commit `2072a27`, branche `recu/D-023c-01`). L’échec vient du résumé de `verifier.sql`, qui exécute `swend_en_cours()`, fonction interne non exécutable par le rôle de lecture ; le bloc d’assertions qui le précède (déclencheurs de fermeture et de paire actifs, fermeture sans push, droits, moteur d’ouverture à jour) n’appelle pas cette fonction et n’a levé aucune erreur : c’est une déduction de l’ordre d’exécution, pas une vérification rejouée. App publiée ensuite, le 04/10 (gh-pages `a0b3b0a`, source `f91595a`) : ordre migration puis app respecté. Déclencheur `trg_verrou_un_swend_par_paire` actif au contrôle en lecture seule du 15/10 (préconditions de `D-027-01`). Restent : le résumé de vérification (chats, chats fermés, messages système, doublons de Swends en cours), à relire en lecture seule sans appeler `swend_en_cours()` ; instantanés de parité QA à rafraîchir ; test réel humain à faire. Historique : QA OK le 03/10 (régression complète : métier 1526/0, E2E 783/0, 30/30 scénarios ; garde-fous 147/0). Règle « un Swend en cours par paire » rendue globale le 04/10 : métier 1546/0 ; E2E 28/30 scénarios au premier passage, les 2 autres (`26_delai_minimum`, `27_fuseaux_horaires`) créaient un second Swend pour une paire déjà en cours — tests adaptés (Swend précédent annulé), puis 25/0 et 24/0. Migration `20261003010000_nouveau_swend.sql` et change packet `supabase/changements/D-023c-01/` (niveau 1, aucune donnée modifiée) préparés et répétés en local, exécutés avant le déploiement de l’app correspondante.

---

## D-027 — « En cas d’imprévu » : chercher, revenir, se désister, annuler

**Statut : Validée**  
**Décidée : 12/10/2026** (règles validées par les fondateurs, décisions complémentaires du 12/10 sur H-3, l’annulation, les conversations, l’envoi groupé, l’échéance à H et la réactivation d’une personne sans compte)  
**Révisée : 20/10/2026** (décision d’Eliot : H-3 devient la limite ferme pour résoudre un imprévu ; la recherche jusqu’à H est abandonnée — points 7, 10, 11 et 13)

### Décision
Le parcours d’imprévu d’un titulaire, de la première demande jusqu’à l’annulation éventuelle. L’app tutoie.

**Chercher quelqu’un**
1. Depuis un Swend scellé, `Un imprévu ?` ouvre directement l’écran des remplaçants : « Tu ne peux plus être là ? / Sollicite l’un de tes remplaçants :) ».
2. Plusieurs demandes en parallèle, la première acceptation gagne. Bouton adaptatif (`Demander à Kevin`, `Envoyer 2 demandes`) et confirmation avant l’envoi : une personne, « Envoyer la demande à Kevin ? / S’il accepte, il prendra ta place et tu ne pourras plus revenir en arrière. » ; plusieurs, « Envoyer la demande ? / La première personne qui accepte prendra ta place. / Une fois ta place prise, tu ne pourras plus revenir en arrière. ». Un même envoi peut mélanger personnes inscrites et personnes sans compte : un seul parcours, la base crée toutes les demandes ensemble ; le canal de remise diffère (notification, ou message / lien selon le mécanisme existant).
3. Attente : « C’est envoyé. / La première personne qui accepte prendra ta place. », liste « Kevin — En attente — Discuter », action secondaire `Solliciter quelqu’un d’autre`, aucun bouton principal artificiel.
4. `Solliciter quelqu’un d’autre` repropose les personnes prévues pas encore sollicitées ; `Ajouter une personne` est toujours possible ; une personne qui a refusé n’est pas reproposée. Pas d’annulation demande par demande. L’annulation du Swend reste le dernier recours.

**Quelqu’un accepte**
5. « Kevin a accepté. / Il prendra ta place le jour J. » Les autres demandes en attente deviennent inactives, leurs conversations restent accessibles ; pas de message « Les autres demandes ont été clôturées » ; `Solliciter quelqu’un d’autre` disparaît. Plus de retour en arrière : le titulaire ne reprend pas sa place et ne remplace pas Kevin.
6. Confidentialité entre personnes de confiance : jamais l’identité ni le nombre des autres. Les personnes en attente reçoivent « Plus besoin de répondre / La place a été prise pour ce Swend. » ; celles qui avaient refusé, rien.
7. Le remplaçant peut dire `Je ne peux finalement plus venir` (avec confirmation), sans choisir son remplaçant. Les demandes qui étaient en attente avant son acceptation sont **réactivées automatiquement** (on peut de nouveau y répondre, le titulaire n’a rien à refaire) ; les refus restent des refus (**dès H-3 : pas de réactivation, le désistement annule le Swend**, point 10). Push aux personnes réactivées : « Ta réponse est finalement attendue / La place est à nouveau disponible pour ce Swend. » Le titulaire voit « Kevin ne peut finalement plus venir. / Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire. » ; `Solliciter quelqu’un d’autre` revient. **Personne sans compte réactivée** : sa demande redevient active selon les mêmes règles, mais jamais en silence : le titulaire voit `Renvoyer le message à Thomas`, avec le message / lien de demande actualisé, prêt à partager par le mécanisme existant (aucune infrastructure SMS).

**Le titulaire peut finalement venir**
8. Avant toute acceptation : `Je peux finalement venir` (confirmation courte). Il redevient participant normal, toutes les demandes en attente sont closes, les refus ne reçoivent rien, les conversations restent accessibles. Push aux personnes en attente : « Plus besoin de répondre / Eliot pourra finalement être là pour ce Swend. » L’action disparaît dès qu’une personne a accepté.

**Personne ne peut**
9. Tout le monde a refusé : « Personne n’a pu prendre ta place. / Tu peux encore solliciter quelqu’un d’autre. » ; `Solliciter quelqu’un d’autre` s’il reste des personnes prévues, sinon `Ajouter une personne`, puis en dernier recours `Je n’ai personne d’autre`. Push au titulaire seulement quand la dernière demande active devient refusée : « Personne n’est disponible pour l’instant / Tu peux solliciter quelqu’un d’autre. »
10. **H-3, limite ferme** (révisé le 20/10/2026, décision d’Eliot ; objectif : éviter une recherche trop tardive et pouvoir prévenir le restaurant dès qu’un problème entraîne l’annulation). Dès H-3 inclus (3 heures avant l’heure du Swend), plus aucune recherche ni réponse :
    - à H-3, toute recherche de remplacement non résolue (imprévu déclaré, aucun remplaçant sélectionné de ce côté) entraîne l’annulation du Swend : demandes en attente closes, plus aucune acceptation ; le titulaire qui cherchait est prévenu (« Le Swend est annulé / Personne n’a pu prendre ta place à temps. »), l’autre titulaire aussi (« Le Swend est annulé / Eliot ne pourra finalement pas être là. »), les personnes en attente aussi (« Le Swend est annulé / Tu n’as plus besoin de répondre. »), le remplaçant sélectionné de l’autre côté s’il existe (« Tu n’auras finalement pas besoin de prendre la place de David. »), celles qui avaient refusé, rien ; puis le parcours d’après annulation ;
    - dès H-3 inclus, tout nouvel imprévu d’un participant attendu entraîne l’annulation immédiate, sans lancer de recherche : un titulaire non remplacé annule depuis `Un imprévu ?` (`Annuler le Swend`, confirmation « Annuler ce Swend ? ») ;
    - dès H-3 inclus, le désistement du remplaçant sélectionné entraîne l’annulation immédiate, sans réactivation des demandes : le titulaire de son côté est prévenu (« Le Swend est annulé / Kevin ne peut finalement plus venir. »), l’autre titulaire reçoit « Eliot ne pourra finalement pas être là. » sans rien apprendre du remplacement ;
    - un Swend dont les participants attendus restent disponibles est maintenu ;
    - aucune notification automatique au restaurant (le suivi interne des réservations affiche « Annuler la réservation au restaurant »).
    *Règle précédente abandonnée (12/10) : sans imprévu déclaré à H-3, une recherche pouvait encore être lancée jusqu’à H ; un désistement après H-3 réactivait les demandes et la recherche continuait jusqu’à H.*
11. **H, limite absolue** : après H, aucune action d’imprévu ; gel à H (D-023a) inchangé. Depuis le 20/10, aucune recherche ne peut plus être en cours à H (point 10) : l’annulation automatique à H prévue le 12/10 devient sans objet ; le gel à H reste le filet de sécurité (demande encore en attente close si l’échéance n’a pas tourné).
12. `Je n’ai personne d’autre` : « Tu n’as personne d’autre ? / Sans quelqu’un pour prendre ta place, le Swend ne pourra pas avoir lieu. », principal `Ajouter une personne`, secondaire `Annuler le Swend`, confirmation « Annuler ce Swend ? / Cette action est définitive. L’autre personne sera prévenue. ». Aucune pénalité ni score.

**Annulation**
13. Plus de bouton générique `Annuler le Swend` sur la fiche : une annulation décidée par un titulaire passe uniquement par `Un imprévu ?` → recherche → `Je n’ai personne d’autre` → `Annuler le Swend` (dès H-3 : `Un imprévu ?` → `Annuler le Swend` directement, point 10). Un titulaire dont la place a été prise ne peut plus annuler lui-même. Les annulations système ou opérationnelles restent possibles (double remplacement, H-3, H, réservation impossible…).
14. L’autre titulaire ne voit jamais les coulisses : « Le Swend est annulé / Eliot ne pourra finalement pas être là. », jamais « Eliot n’a trouvé personne… ».
15. Après annulation, un chat s’ouvre immédiatement entre les deux titulaires (sans push spécifique) ; la fiche montre `Discuter` et `Faire un nouveau Swend` ; ouvert sans limite arbitraire ; fermé selon D-023c si les deux scellent un nouveau Swend ensemble.
16. Les conversations existantes avec les personnes de confiance réellement sollicitées (ou avec lesquelles une conversation existe) restent accessibles **et ouvertes à l’écriture** après annulation ; une personne seulement prévue, jamais sollicitée, ne gagne aucun accès. Aucune nouvelle conversation créée par l’annulation. Fermeture paire par paire si un nouveau Swend est scellé entre ces deux personnes ; rien ne ferme si le titulaire fait un nouveau Swend avec quelqu’un d’autre.
17. Double remplacement (V1) : annulation. Titulaires : « Le Swend est annulé. / Ni toi ni David ne pourrez finalement être là. » ; chaque remplaçant : « Le Swend est annulé / Tu n’auras finalement pas besoin de prendre la place d’Eliot. » (jamais l’identité de l’autre remplaçant) ; personnes en attente : « Le Swend est annulé / Tu n’as plus besoin de répondre. » ; refus : rien.
18. Chaque côté est indépendant : l’autre titulaire ne voit rien des recherches et n’est informé que des conséquences certaines ; de même pour les remplaçants. États minimaux : En attente, Refusé, Clôturée, Désisté, sélectionné. Push seulement quand une action devient attendue, cesse de l’être, ou qu’un changement certain touche le Swend ; jamais une push par transition technique.

### Mise en œuvre en 4 lots
1. États et actions (base) : déclaration d’imprévu par côté, clôtures à mémoire, envoi groupé, `Je peux finalement venir`, réactivation au désistement (avec message à renvoyer pour une personne sans compte), notifications de l’imprévu.
2. Annulation et conversations (base) : annulation réservée au titulaire non remplacé, textes, chat d’annulation entre titulaires, conversations d’imprévu ouvertes à l’écriture après annulation et fermeture paire par paire.
3. Application : écran « Un imprévu ? » réécrit, retrait du bouton d’annulation de la fiche et de l’annulation demande par demande.
4. Échéances H-3 et H (base et planification), rappels adaptés. *Révisé le 20/10 : l’échéance H-3 ferme est traitée à part (paquet `D-027-03`) ; reste au lot 4 l’harmonisation des rappels.*

### Choix techniques (lot 1, 12/10)
- « Imprévu déclaré » : table interne `imprevus_declares` (une ligne par côté, aucun accès de l’app : l’autre titulaire ne doit jamais savoir qu’un côté cherche), posée par la base dès qu’une demande de ce côté existe, effacée par `Je peux finalement venir` (et, tant que l’app actuelle l’utilise, par l’annulation de la dernière demande sans refus ni désistement). `etat_cote_titulaire()` (rappels, destination au clic) la lit : après un retour, les refus restent mais le titulaire n’est plus en imprévu ; retirer de sa liste une personne qui a refusé ne fait plus sortir de l’imprévu.
- Clôtures à mémoire : table interne `clotures_demandes` (`acceptation` + fiche acceptée, ou `autre_cote` + état d’avant). Seules ces clôtures sont réversibles au désistement ; une clôture antérieure à D-027 garde l’ancien comportement (la personne redevient sollicitable sans demande). Une demande n’est rendue « en attente » que si son côté est toujours en imprévu ; sinon la personne redevient simplement prévue.
- Même personne des deux côtés (D-012) : au désistement, sa fiche de l’autre côté retrouve son état d’avant (en attente → push « Ta réponse est finalement attendue » ; prévue → prévue), seulement si ce côté n’a personne ; jamais de push à l’autre titulaire.
- « Clôturée » par un retour du titulaire : la fiche redevient « prévue » (sollicitable lors d’un prochain imprévu) avec l’événement `retour_titulaire` dans la conversation ; la réactivation ajoute l’événement `demande_reactivee`.
- Personne sans compte réactivée : `remplacants.message_a_renvoyer`, posé et effacé par la base seulement ; `marquer_message_renvoye()` quand le titulaire a ouvert le message (Messages ou WhatsApp) ; effacé aussi dès que la demande n’est plus en attente. L’app actuelle affiche `Renvoyer le message à Thomas` sur la fiche du Swend et dans `Un imprévu ?`.
- Envoi groupé : `envoyer_demandes_remplacement(ids[])`, tout ou rien, renvoie le canal de remise de chaque demande ; `envoyer_demande_remplacement(id)` en est le cas d’une personne (app actuelle).
- Notifications envoyées par les fonctions (`pousser_personne`, `pousser_titulaire`, internes) avec le texte de leur contexte ; le déclencheur ne garde que l’indisponibilité spontanée (D-008). Textes non donnés par la spec, proposés et acceptés avec le plan : acceptation au titulaire « Kevin a accepté / Kevin sera là à ta place le jour J. » (formulation validée le 12/10, neutre : le genre d’une personne n’est jamais déduit de son prénom) ; désistement au titulaire « Kevin ne peut finalement plus venir », avec « Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire. » si au moins une demande de son côté a été réactivée, sinon « Tu peux solliciter quelqu’un d’autre. ». Dernier refus : push vers la fiche du Swend.

### Écarts restants après le lot 1
- Écrans, confirmations et tutoiement de l’imprévu : lot 3 (l’app actuelle garde « Lui demander » personne par personne, « Annuler la demande », le bouton d’annulation de la fiche, le vouvoiement).
- Annulation (textes, droit du titulaire remplacé, chat d’annulation, conversations après annulation) et double remplacement (textes ; les personnes en attente du second côté reçoivent « Plus besoin de répondre / La place a été prise pour ce Swend. ») : lot 2.
- Échéances H-3 et H : lot 4 (le rappel de H-3 « annule le Swend… » reste envoyé d’ici là).

### Choix techniques (lot 2, 15/10)
- **Annulation unique** : une seule fonction interne, `appliquer_annulation()`, pour toute annulation (titulaire, double remplacement ; plus tard H-3, H, raison opérationnelle) : demandes en attente des deux côtés closes, statut, date, motif (`pactes.annule_motif` : `titulaire`, `double_remplacement`, réservé `echeance_h3`, `echeance_h`, `operationnelle` ; posé par la base seulement), notifications du §13–17, chat d’annulation, dans la même transaction. `annule_par` n’est posé que pour une annulation par un titulaire. Une push par personne, celle du remplaçant sélectionné en priorité (une même personne en attente d’un côté et sélectionnée de l’autre ne reçoit que la seconde). Rien pour l’auteur, les refus, les désistements, les personnes seulement prévues.
- **Titulaire remplacé** : `annuler_swend()` refuse `remplacement_accepte` si le côté de l’appelant a un remplaçant sélectionné ; l’autre titulaire (non remplacé) peut toujours annuler. Le remplaçant n’annule jamais (`non_autorise`). Les verrous (Swend puis fiches) rendent l’issue unique face à une acceptation simultanée.
- **Chat d’annulation** : même infrastructure que le chat après le Swend (D-023b), distinguée par `chats_apres_swend.nature = 'annulation'` ; participants : les deux titulaires seulement, jamais un remplaçant ; ouvert dans la transaction de l’annulation, sans push d’ouverture (les push de message habituelles s’appliquent ensuite) ; pas de destinataire sans compte → pas de chat. Une ligne par Swend : le chat après le Swend normal ne peut plus jamais s’ouvrir pour un Swend annulé (le moteur ne traite de toute façon que les Swends `confirme`). « Faire un nouveau Swend » et la fermeture au scellement (D-023c) s’y appliquent sans changement. Lecture : `mes_chats_swend()` (nouvelle, les deux natures, pour l’app du lot 3) ; `mes_chats_apres_swend()` (app publiée) ne renvoie que la nature `apres_swend`, si bien que l’app actuelle n’affiche jamais un chat d’annulation comme un « Alors, ce Swend ? ».
- **Conversations conservées** (`fil_conserve_apres_annulation()`) : Swend scellé puis annulé, fiche non retirée, et une conversation qui existe : une demande a été envoyée (événement `demande_envoyee` : personne réellement sollicitée, qu’elle ait accepté, refusé, se soit désistée, ou que sa demande ait été close ou annulée ensuite) **ou** au moins un message a été échangé. Lecture et écriture, sans limite de date, jusqu’à la fermeture. Une personne seulement prévue, sans message, n’obtient rien (fil vierge, aucun accès, aucune écriture). Après l’annulation, aucune nouvelle demande (`swend_inactif`), donc aucune nouvelle conversation.
- **Précision P1 — validée par Eliot le 15/10/2026** : une conversation où des messages ont déjà été échangés reste accessible et écrivable après annulation, même sans demande de remplacement envoyée ; une personne simplement prévue, sans demande ni échange, ne gagne aucun accès. (Implémentation : `fil_conserve_apres_annulation()` = demande envoyée **ou** au moins un message.) Origine : message des fondateurs du 12/10/2026 (20:22 UTC, repris à 20:29), « 3. Conversations après annulation / Seules les personnes de confiance qui ont réellement été sollicitées / avec lesquelles une conversation existe conservent cette conversation ouverte à l’écriture. / Une personne simplement prévue mais jamais sollicitée ne gagne aucun accès ou chat supplémentaire lors de l’annulation. », dont la barre oblique était ambiguë (transcrite « (ou …) » au point 16, commit `76956ef`) ; P1 la lève.
- **Fiches retirées** : condition justifiée, pas une exception. Le retrait n’est possible que pour une personne sans demande en cours ni place prise ; il ôtait déjà tout accès (D-023a) avant l’annulation. La règle est « conserver » une conversation accessible, pas en rendre une : une fiche retirée avant l’annulation ne récupère rien. Pour qu’aucun retrait ne coupe ensuite une conversation conservée, `retirer_remplacant()` refuse désormais `swend_inactif` sur un Swend annulé ou maintenu.
- **Date de mise en service** : aucune. La règle vaut pour toute annulation ; en production (lecture seule du 15/10) aucun Swend scellé puis annulé n’existe, donc aucune conversation ne serait « rouverte ». Le paquet le revérifie et s’arrête sinon (arbitrage produit nécessaire : redonner l’accès ou non).
- **Fermeture paire par paire** : au scellement d’un Swend entre A et B, chaque conversation conservée dont les deux membres (titulaire du côté, personne de confiance) sont exactement A et B est fermée : table interne `fils_imprevu_fermes`, événement `fil_ferme` dans la conversation, lecture conservée, écriture refusée (RLS), aucune push. Aucune autre conversation : un nouveau Swend du titulaire avec quelqu’un d’autre, de la personne de confiance avec un tiers, ou de l’autre titulaire avec elle ne ferme rien.
- **Précision P2 — validée par Eliot le 15/10/2026** : un nouveau scellement entre les mêmes personnes empêche l’annulation de l’ancien Swend de rouvrir leur conversation. (Implémentation : un Swend entre A et B scellé après le scellement du Swend annulé — avant ou après l’annulation — ferme leur conversation conservée ; s’il est scellé avant l’annulation, la conversation est fermée dès l’annulation, même issue quel que soit l’ordre ; un Swend entre A et B scellé avant le Swend annulé n’est pas « nouveau » et ne ferme rien.)
- **Verrou par paire** : un verrou consultatif par paire sérialise annulation et scellement simultanés entre les deux mêmes personnes. Preuve conservée (`qa/preuves/2026-10-15_D-027-02_verrou_paire.txt`, script `qa/metier/preuve_verrou_paire.sh`, 15 essais par variante, 5 par ordre) : avec le verrou, 15 réussis / 0 échec ; sans le verrou (clé rendue aléatoire le temps du test, fonction d’origine restaurée et vérifiée par empreinte), 3 réussis / 12 échecs — scellement tenu ouvert 0/5, annulation tenue ouverte 0/5, lancés ensemble 3/5 ; chaque échec : Swend annulé, nouveau Swend scellé, conversation restée ouverte, aucun événement `fil_ferme`. La course 18 de `concurrence.sh` (9 essais, dont 6 avec une transaction tenue ouverte) échoue donc de façon déterministe sans le verrou. (Une première mesure, non conservée, avait donné 0 réussi / 9 échecs sans verrou.)
- **Numéro du titulaire (D-024) découplé et inchangé** : `telephone_titulaire_accessible()` appelle `fiche_acces_d023a()`, corps identique à l’ancienne règle d’accès (même empreinte, vérifiée par le paquet) ; les droits de conversation ci-dessus n’ouvrent aucun numéro. « Conserver l’ancienne règle » signifie, d’après le code et D-023a/D-024 : après annulation, le remplaçant **sélectionné** garde le numéro de son titulaire (il le gardait déjà), les personnes sollicitées non sélectionnées et les personnes prévues n’en ont aucun (elles le perdaient déjà). « Aucun numéro après annulation » retirerait le numéro au remplaçant sélectionné : ce serait une restriction nouvelle, non décidée, donc non appliquée.
- **Limites connues** : un message inséré exactement pendant la transaction qui ferme sa conversation peut passer (contrôle RLS sans verrou), comme pour D-023c ; une annulation écrite directement en base (SQL de service, hors `annuler_swend()` / double remplacement) n’ouvre pas de chat d’annulation et ne pose pas de motif.

### Écarts restants après le lot 2
- Rien n’est visible des conversations conservées ni du chat d’annulation tant que l’app du lot 3 ne les expose pas : l’app publiée (lot 1) garde les conversations d’un Swend annulé en lecture seule (règle locale) et ne lit pas `mes_chats_swend()`. Le lot 2 ne doit pas être mis en production avant une app du lot 3 compatible (voir « Mise en production »). *Levé le 20/10 : app du lot 3 publiée, puis D-027-02 exécuté.*
- Écrans de l’imprévu, retrait du bouton d’annulation de la fiche et de l’annulation demande par demande, tutoiement : lot 3.
- Échéances H-3 et H (motifs `echeance_h3`, `echeance_h` réservés) : lot 4.

### Choix techniques (lot 3, 15/10)
Application seulement, aucune migration nouvelle hors `D-027-02` (une fonction de plus, ci-dessous). Découpé en **3a** (compatibilité, écran `Un imprévu ?`, fiche) puis **3b** (conversations et écrans après annulation). L’app fonctionne sur la base actuelle (D-027-01) et sur la base avec D-027-02 ; ni mesure d’adoption, ni rechargement automatique, ni contrôle de version (Go du 15/10).

**3a — compatibilité et écran `Un imprévu ?`**
- État de mon côté lu par `destination_rappel()` (en production : `imprevu` ⇔ mon côté cherche, sans remplaçant sélectionné), mes fiches et mes événements (`desistement`, `demande_envoyee`) : jamais celui de l’autre côté. Phases : choix, attente (`C’est envoyé.`), personne n’a pu, accepté ; en-tête de désistement (« Kevin ne peut finalement plus venir. » + réactivées ou non) tant qu’aucune nouvelle demande n’est partie.
- Actions : `envoyer_demandes_remplacement(ids[])` (sélection multiple, tout ou rien, personnes inscrites et sans compte dans le même envoi), `je_peux_finalement_venir()`, `annuler_swend()` ; aucune fonction du lot 2 n’est nécessaire. Refus de la base traduits au tutoiement (`TextesImprevu.erreur`), dont `remplacement_accepte` (base avec D-027-02).
- Écran : cases à cocher (personnes avec compte d’abord), bouton adaptatif et confirmations validées ; personne sans compte : après l’envoi, « Demande envoyée à Tom / Tom n’a pas encore de compte Swend : envoie-lui un message… » (`Envoyer le message`, `Plus tard`), puis `Envoyer le message` dans la liste d’attente et `Renvoyer le message à Tom` après une réactivation (fiche et écran) ; liste d’attente avec `En attente` / `Indisponible` et `Discuter` ; `Solliciter quelqu’un d’autre` (mode sélection, `Retour`) ; `Ajouter une personne` (feuille d’ajout, « Lui demander de prendre ma place », confirmation) ; `Je peux finalement venir` (confirmation courte, retour à la fiche) ; accepté : « Kevin a accepté. / Kevin sera là à ta place le jour J. », `Écrire à Kevin`, plus aucune action d’imprévu.
- **Dernier recours** (`Je n’ai personne d’autre` → « Tu n’as personne d’autre ? » → `Ajouter une personne` / `Annuler le Swend` → « Annuler ce Swend ? ») : proposé quand personne n’a pu prendre la place, et — interprétation — quand il n’y a plus personne à solliciter (liste vide ou toutes les personnes indisponibles). Jamais pendant l’attente, jamais après une acceptation. Sur la base sans D-027-02, un titulaire remplacé n’a donc aucun chemin d’annulation dans l’app (la base actuelle l’accepterait encore par appel direct).
- Fiche : plus de bouton générique `Annuler le Swend` ; bloc « En cas d’imprévu » au tutoiement, avec l’en-tête de la situation pendant un imprévu. `Annuler la demande` retiré de « Modifier ma liste ».
- Formulation validée le 20/10 : confirmation à une personne « En acceptant, Kevin prendra ta place et tu ne pourras plus revenir en arrière. » au lieu de « S’il accepte, il… » (le genre n’est jamais déduit d’un prénom, même règle que l’acceptation du 12/10).

**3b — après l’annulation**
- Chat d’annulation : lu par `mes_chats_swend()` ; si la fonction est absente (base sans D-027-02, erreur PostgREST `PGRST202`), repli sur `mes_chats_apres_swend()` sans chat d’annulation. Sur la fiche d’un Swend annulé : bloc « APRÈS L’ANNULATION », `Discuter`, « Avec David », `Faire un nouveau Swend` (D-023c) ; jamais « Alors, ce Swend ? » ni carte d’invitation (pas de push d’ouverture) ; carte d’accueil seulement pour un message non lu (« David vous a écrit / Swend annulé · Au père Lapin »). La push d’un message dit « Swend annulé · Restaurant » : `envoyer_message_apres_swend()` ajoutée au paquet D-027-02 (10e fonction remplacée, texte seulement).
- Conversations d’imprévu : écriture décidée par la base (`fil_ecriture_ouverte()`, en production), plus par une règle locale ; un refus à l’envoi affiche la conversation terminée. Titulaire : `Reprendre une conversation` / « Reprendre la conversation avec… » quand au moins une est encore écrivable, sinon `Relire une conversation`. Personne de confiance : « Ce Swend a été annulé. », plus « Tu n’auras finalement pas besoin de prendre la place d’Eliot. » pour le remplaçant sélectionné, `Écrire à Eliot` si écrivable, sinon `Relire la conversation`. Un Swend annulé reste dans l’historique d’une personne de confiance tant que la base le lui renvoie (P1), et en disparaît sinon (personne seulement prévue). Aucun numéro ajouté (D-024).
- Conversation fermée par un nouveau Swend (P2) : événement `fil_ferme`, « Un nouveau Swend a été scellé entre vous. / Cette conversation est désormais fermée. », bandeau « Cette conversation est fermée. Elle reste consultable. ». Code d’événement inconnu toléré.
- **Tutoiement des écrans (demande d’Eliot, 15/10)** : le tutoiement partout dans l’app, décision déjà validée, prime sur les anciens libellés. « Votre Swend avec David est annulé. » → « Ton Swend avec David est annulé. » ; « Kevin a pris votre place » → « Kevin a pris ta place » (fiche d’un Swend passé, révélation du chat après le Swend) ; « David vous a écrit » → « David t’a écrit » (cartes d’accueil, fiche, Mes Swends, conversations d’imprévu) ; message de double remplacement de la fiche → « Ni toi ni David ne pourrez finalement être là. » (texte D-027, point 17) ; acceptation inchangée « Kevin sera là à ta place le jour J. ». « Réessayez » → « Réessaie. » dans les écrans du lot (erreur d’envoi d’un message de chat, « Renvoyer le message »). **Push de message** : `envoyer_message_apres_swend()`, déjà redéfinie par D-027-02, envoie « [Prénom] t’a écrit » au lieu de « [Prénom] vous a écrit » pour les deux natures de chat (après le Swend, annulation) ; c’est la seule fonction qui notifie un message (les messages des conversations d’imprévu n’envoient aucune push) ; jusqu’à l’exécution de D-027-02 (20/10/2026), la production gardait « vous a écrit » (version de `chat_apres_swend.sql`, rétablie aussi par le rollback). Les « vous » qui désignent plusieurs personnes restent (« À vous de débriefer. », « entre vous », « Un Swend est déjà en cours entre vous. », « Vous pouvez en reparler ici. », push d’ouverture du chat « Le silence est levé. Vous pouvez maintenant en reparler dans le chat. »).

**Textes du lot 3 — validés le 20/10** (avec deux ajustements : « Tom n’a pas encore de compte Swend. » au lieu de « Tom n’a pas encore Swend », repris dans « Tom n’a pas encore de compte Swend : envoie-lui un message… » ; confirmation à une personne « En acceptant, Kevin prendra ta place et tu ne pourras plus revenir en arrière. ». Le statut « [Prénom] n’a pas encore Swend » des listes et de la création, plus ancien, reste inchangé) : liste vide « Tu n’as encore prévu personne : ajoute une personne qui pourra prendre ta place. » ; personne à solliciter « Personne de ta liste n’est disponible : tu peux ajouter une personne. » ; sélection « Choisis une ou plusieurs personnes de ta liste. » ; « Tom n’a pas encore de compte Swend. » ; ajout « Cette personne recevra directement ta demande de prendre ta place. » / `Lui demander de prendre ma place` ; « Demande envoyée à Tom » / « Tom n’a pas encore de compte Swend : envoie-lui un message pour lui expliquer et lui permettre de répondre depuis l’app. » / `Plus tard` / `Envoyer le message` ; « La demande attend de nouveau sa réponse. » ; retour « Tu peux finalement venir ? / Les personnes qui n’ont pas encore répondu seront prévenues qu’elles n’ont plus besoin de le faire. » (sinon « Tu redeviens simplement participant à ce Swend. »), `Je peux venir`, « C’est noté : tu seras là. » ; heure passée « L’heure du Swend est passée. / Il n’est plus possible de demander à quelqu’un de prendre ta place. » ; refus `remplacement_accepte` « Quelqu’un a déjà accepté de prendre ta place : tu ne peux plus annuler ce Swend. » ; chat d’annulation « APRÈS L’ANNULATION », sous-titre « Swend annulé », état vide « Vous pouvez en reparler ici. » ; `Reprendre une conversation` / « Reprendre la conversation avec… » ; conversation fermée « Un nouveau Swend a été scellé entre vous. / Cette conversation est désormais fermée. » et « Cette conversation est fermée. Elle reste consultable. ».

### Écarts restants après le lot 3
- Échéances H-3 et H : lot 4 ; *révisé le 20/10 : l’échéance H-3 ferme est préparée à part (paquet `D-027-03`, voir « Choix techniques (échéance H-3 ferme) »)*. Les rappels J-7 et J-1 au vouvoiement (« Votre Swend avec [Prénom] approche… », « Votre Swend avec [Prénom], c’est demain… », `rappels_jour_j.sql`) seront harmonisés dans le lot 4, qui traite les rappels.
- **Corrections hors lot à terminer avant les tests humains** (app seulement, aucune fonction serveur) : statut « À vous de répondre » → « À toi de répondre » (`lib/theme/app_theme.dart`, statut des cartes de Swend) ; formulations individuelles restantes à la création et au choix de la date : « D’autres restaurants vous seront bientôt proposés, vous pouvez nous en suggérer : ici » (`creer_pacte_screen.dart`), « Choisissez une date au moins 15 jours à l’avance. » (`delai_minimum.dart`, création et choix de la date), « Cette date n’a pas pu être enregistrée. Rechargez l’app puis réessayez. » (`delai_minimum.dart`, refus d’une date par la base, app périmée). Aucun vrai pluriel dans cette liste.
- Anciennes sessions de l’app : voir « Mise en production » (aucun moyen de forcer un rechargement ; limite acceptée par Eliot le 20/10, aucune confirmation demandée aux comptes).
- **Tests humains des nouveaux parcours à faire** (lots 1 à 3) : aucune demande, annulation, conversation conservée, double remplacement ni fermeture par un nouveau Swend n’a encore été exercé en production. La réussite des jobs pg_cron après la migration ne prouve que l’absence de régression des traitements planifiés, pas le fonctionnement des nouveaux parcours.

### Choix techniques (échéance H-3 ferme, 20/10)
Migration `20261020000000_echeance_h3.sql`, paquet `D-027-03` (niveau 2, **sans validation**), app (non publiée). `appliquer_annulation()` du lot 2 n’est pas modifiée : notifications d’annulation, chat d’annulation, conversations conservées et confidentialité restent celles du lot 2.
- **Instant** : H-3 = `echeance_rappel(date, 'j0')`, le même instant que le rappel du Jour J ; inclus (« dès H-3 »). Exemple : Swend du mardi 17 novembre à 19h00 (heure de Paris) → H-3 = mardi 17 novembre à 16h00. Jugé par l’horloge du serveur **au moment où l’action peut être validée** : l’heure est lue (`clock_timestamp()`) une fois les verrous du Swend et de ses fiches obtenus, pas au début de la requête ni de la transaction (`now()`). Une action validée avant H-3 aboutit ; une action qui ne peut être validée qu’à H-3 ou après est refusée, même si la requête est partie avant H-3 (par exemple en attente du verrou tenu par une autre transaction).
- **Actions refusées dès H-3** (`echeance_h3`) : `envoyer_demandes_remplacement()` (et `envoyer_demande_remplacement()`), `ajouter_et_demander_remplacement()`, `annuler_demande_remplacement()` (ancienne app), `je_peux_finalement_venir()`, `repondre_demande_remplacement()` (accepter **et refuser** : un refus tardif aurait déclenché « Personne n’est disponible pour l’instant / Tu peux solliciter quelqu’un d’autre. », devenu faux). Restent possibles : `annuler_swend()` (nouvel imprévu d’un titulaire, motif `titulaire`), gérer sa liste (préparation), signaler une indisponibilité (personne seulement prévue), écrire dans une conversation.
- **Désistement dès H-3** : `se_desister_du_remplacement()` marque le désistement (événement dans la conversation), prévient le titulaire de son côté (« Le Swend est annulé / Kevin ne peut finalement plus venir. ») puis annule (`appliquer_annulation`, côté absent = ce côté, motif `echeance_h3`, sans auteur) : l’autre titulaire reçoit « Eliot ne pourra finalement pas être là. » ; aucune demande réactivée, aucune « Ta réponse est finalement attendue ».
- **Recherche non résolue à H-3** : `appliquer_echeances_h3()` (interne), pour chaque Swend `confirme` non figé dont H-3 est atteint, avec au moins un côté en imprévu sans remplaçant sélectionné : verrous du Swend puis de ses fiches (même ordre que les actions), état relu sous verrou, push « Personne n’a pu prendre ta place à temps. » au(x) titulaire(s) qui cherchaient, puis `appliquer_annulation` (un seul côté : l’autre titulaire est prévenu ; deux côtés : chacun reçoit sa propre push). Idempotente.
- **Rattrapage après H (précisé le 20/10 à la demande d’Eliot : annulation systématique dès H-3)** : si aucun traitement n’a réussi entre H-3 et H (jobs en échec), le premier qui réussit ensuite annule le Swend, quel que soit le retard — le job de l’échéance, le moteur des rappels, ou le gel à H, qui applique désormais l’échéance **avant** de figer quoi que ce soit (`figer_swends_passes()` redéfinie, 8e fonction du paquet). Un tel Swend n’est donc jamais figé : demandes closes avec « Tu n’as plus besoin de répondre. » (jamais « La demande n’est plus d’actualité »), aucun événement de fin, chat d’annulation et conversations conservées comme pour toute annulation, et jamais de chat après le Swend (son moteur ne traite que les Swends figés). Push d’annulation envoyées même longtemps après H (l’annulation doit être connue ; pas de fenêtre de 12 heures comme pour le gel). Après H-3, l’état d’un Swend ne peut plus changer sans annulation immédiate (recherche, réponse et retour refusés ; désistement et nouvel imprévu annulent) : un côté encore en imprévu sans remplaçant l’était à H-3, et un Swend maintenu valablement n’est jamais touché (figé comme avant, chat après le Swend). Garde-fou : un Swend déjà figé (gel antérieur à la règle) n’est jamais repris ; le paquet vérifie qu’aucun Swend passé n’est resté en imprévu non résolu. *(Corrige le bilan précédent, qui présentait à tort le gel à H comme filet de sécurité : il figeait un tel Swend au lieu de l’annuler.)*
- **App (même correction)** : dans l’historique d’une personne de confiance, un Swend annulé suit toujours la règle P1 (gardé tant que la base le renvoie), même une fois son heure passée ; auparavant, `_passeSansMoi` le masquait dès H à une personne non sélectionnée (cas qui existait déjà pour un Swend annulé avant H puis dépassé).
- **Planification (révisée le 20/10 à la demande d’Eliot)** : nouveau job pg_cron `swend-echeance-h3`, **chaque minute**, commande `select public.appliquer_echeances_h3()`, créé par le paquet `D-027-03` dans la transaction de la migration (`supabase/planification/echeance_h3_pg_cron.sql`, hors migration) et retiré par son rollback ; même rôle et même base que `swend-rappels` (vérifié par le paquet). L’échéance reste aussi appliquée **en tête** du moteur des rappels (`envoyer_rappels_dus()`, job `swend-rappels`, toutes les 5 minutes, **fréquence inchangée**), donc avant tout rappel du Jour J : un Swend annulé à H-3 ne reçoit ni « Ton Swend est en péril ! » ni « Est-ce que tu vas vraiment … ». Le rappel « cherche » du Jour J n’est plus jamais envoyé. **Aucune notification en double** : chaque passage verrouille le Swend et relit son état ; un Swend déjà annulé n’est plus traité ; l’anti-doublon des rappels est inchangé (testé : job et moteur simultanés, 3 échéances simultanées).
- **Deux délais distincts** : (1) **blocage strict des actions** — dès H-3 pile, la base refuse rechercher, répondre, revenir (`echeance_h3`), et un désistement annule ; cela ne dépend d’aucun job. (2) **délai de traitement automatique** — l’annulation d’une recherche non résolue a lieu au passage suivant d’un job : normalement dans la minute qui suit H-3 ; si seul le job de la minute est en défaut, au passage suivant de `swend-rappels` (au plus 5 minutes). **Ce délai n’est pas garanti** : si les jobs échouent ou si pg_cron s’arrête, l’annulation attend la prochaine exécution réussie ; entre-temps le Swend reste « confirmé » sans recherche possible, sans annulation ni push. Elle a lieu quand même au premier traitement réussi, même après H (rattrapage ci-dessus).
- **Ce qui est vérifié localement / ce qui demande pg_cron** : sur le banc (pg_cron absent), `appliquer_echeances_h3()` et les actions sont testées à instant contrôlé (juste avant H-3, à H-3 pile, après H-3, après H), idempotence, absence de doublon avec le moteur des rappels, courses réelles sur connexions séparées ; la répétition du paquet simule `cron.job` et `cron.schedule` / `cron.unschedule` (signatures de pg_cron 1.6, version de production) : création du job, refus s’il existe déjà, même rôle et même base que `swend-rappels`, exécution de la commande enregistrée, retrait au rollback. Seule la production peut montrer que pg_cron **déclenche** le job chaque minute : après exécution (lecture seule), `cron.job` (job actif, `* * * * *`, rôle et base de `swend-rappels`), puis `cron.job_run_details` (exécutions de `swend-echeance-h3` en `succeeded`, environ une par minute, durée courte ; `swend-rappels`, `swend-gel-a-h` et `swend-chat-apres` toujours `succeeded`). Le délai réel à H-3 sur un vrai Swend ne sera observé qu’au premier cas réel (test humain).
- **Concurrence** : acceptation validée avant H-3 et échéance simultanée → l’échéance attend le verrou puis voit la place prise (Swend maintenu) ; acceptation demandée avant H-3 mais qui attend le verrou du Swend jusqu’après H-3 → refusée (`echeance_h3`, demande toujours en attente), puis Swend annulé par l’échéance ; acceptation lancée à H-3 ou après → refusée, Swend annulé ; 3 échéances simultanées, ou le job de la minute et le moteur des rappels au même moment → une seule annulation, une push par personne, aucun rappel du Jour J ; jobs en échec jusqu’après H puis reprise simultanée (gel deux fois, échéance, chat après le Swend, rappels) → une seule annulation, jamais figé, seul le chat d’annulation, aucun doublon (`qa/metier/concurrence.sh`, courses 6, 6 ter, 7, 7 bis, 7 ter, 8 bis ; course 8 : gel d’un Swend maintenu).
- **App** : dès H-3 (horloge de l’appareil ; la base reste seule juge), `Un imprévu ?` n’offre plus de recherche : côté en recherche, « Personne n’a pu prendre ta place à temps. / À partir de 3 heures avant le Swend, on ne peut plus chercher personne : le Swend va être annulé. », sans action ; sans imprévu, « Tu ne peux plus être là ? / À partir de 3 heures avant le Swend, il n’est plus possible de chercher quelqu’un pour prendre ta place. Si tu ne peux pas venir, le Swend sera annulé. », `Annuler le Swend` → confirmation validée « Annuler ce Swend ? ». Pendant la recherche, avant H-3 : « Si personne n’a accepté avant mardi 17 novembre à 16h00, le Swend sera annulé. » (Swend du mardi 17 novembre à 19h00, heure de Paris ; le « 17h00 » d’une première présentation venait d’une donnée de test d’un Swend à 20h00). Bloc « En cas d’imprévu » de la fiche : même en-tête dès H-3. Confirmation du désistement dès H-3 : « À partir de 3 heures avant le Swend, personne d’autre ne pourra prendre la place d’Eliot : le Swend sera annulé. ». Refus `echeance_h3` : « Il est trop tard : à partir de 3 heures avant le Swend, on ne peut plus chercher ni accepter de remplaçant. ». Borne explicite (« À partir de 3 heures avant le Swend » au lieu de « À moins de 3 heures du Swend ») demandée par Eliot le 20/10.
- **Textes** : push « Le Swend est annulé / Personne n’a pu prendre ta place à temps. » et « Le Swend est annulé / Kevin ne peut finalement plus venir. » **acceptées par Eliot le 20/10** ; écrans et messages ci-dessus, borne reformulée à sa demande.
- **Transition** : l’app fonctionne sur les deux bases, mais chaque ordre laisse une fenêtre où l’écran et la base divergent pour un Swend situé entre H-3 et H (détail : `paquet.md` de D-027-03, « Ordre d’exécution ») ; exécution recommandée quand aucun Swend scellé n’a son heure dans les 3 heures, base puis app dans la foulée.
- **QA (20/10, commit `efbcaad`)** : suite `99h_echeance_h3` 51/0 ; suites `98` (préparation avant H-3) et `99` (Jour J « cherche » → annulation) réalignées ; concurrence : 5 courses H-3 (6, 6 ter, 7 — 10 courses de part et d’autre de H-3 : 5 acceptées, 5 annulées —, 7 bis, 7 ter) remplaçant les 2 courses « acceptation à H » devenues impossibles ; la course 6 ter échoue si l’heure est lue au début de la transaction (preuve `qa/preuves/2026-10-20_D-027-03_mutation_6ter.txt`) ; métier complet 1891/0 ; Dart 182/0 ; répétition du paquet conforme (9 refus attendus, job créé puis retiré), suites SQL sur base issue du paquet 1116/0 ; E2E `32_echeance_h3` 30/0 (base avec l’échéance) et 16/0 (base de production actuelle) ; E2E complet sur la base avec l’échéance 34/34, 948/0, et sur la base de production actuelle (`QA_BASE=avant-D-027-03`) 34/34, 934/0.

### Raison
Un imprévu doit se gérer en un seul parcours, sans revirement après une acceptation, sans travail inutile pour le titulaire après un désistement, sans jamais exposer les coulisses à l’autre titulaire ni aux autres personnes de confiance, et avec une limite claire avant le rendez-vous.

### Remplace / précise
Remplace D-004. Révise D-022 (lot 2). Complète D-023b (chat d’annulation, lot 2). Précise D-015 (notifications de l’imprévu), D-021 (état « cherche » et rappels), D-002, D-003, D-009, D-012.

### Mise en production
Lot 1 : **en production depuis le 15/10/2026**. App du lot 1 publiée le 13/10 (gh-pages `dda243e`, source `503b63a`). Paquet `D-027-01` (niveau 2, empreinte `a24e1e1d4247`, Go d’Eliot du 13/10) appliqué le 15/10 à 07:33 UTC : `sauvegarde`, `appliquer` et `verifier` HTTP 201, `RESULTAT: SUCCES` (reçu `supabase/changements/D-027-01/journal/20261015T073319Z-appliquer.log`, commit `27df1dc`, branche `recu/D-027-01`) ; les 3 tentatives du 13/10 avaient échoué dès l’étape `sauvegarde` (HTTP 401, identifiant de l’environnement d’écriture invalide, aucune écriture). `verifier.sql` : `cotes_en_imprevu` 0, `clotures_memorisees` 0, `messages_a_renvoyer` 0, `fonctions_d027` 8, `fiches` 6 = `fiches_sauvegardees` 6. Contrôles en lecture seule du 15/10 (07:36 UTC) : 0 côté en imprévu, cohérent avec l’état réel (1 Swend `confirme` dont les 4 fiches n’ont ni demande ni sélection ni retrait, 1 Swend en attente de date ; aucune fiche, aucun événement du fil, aucun changement d’état depuis la sauvegarde) ; jobs `swend-rappels` et `swend-gel-a-h` (07:35) et `swend-chat-apres` (07:34 à 07:36) `succeeded` après la migration, aucun échec sur 7 jours. Test réel humain à faire : aucune demande réelle n’a encore exercé le nouveau code. Lots 2, 3 et 4 à cette date (15/10) : à réaliser (annulation, conversations et double remplacement ; écrans, confirmations et tutoiement de l’imprévu ; échéances H-3 et H). QA du 12/10 : régression complète métier 1654/0 (SQL dont `99f_imprevu_etats_actions` 93/0, concurrence avec 2 nouvelles courses, parité, Dart sous 4 fuseaux), E2E 788 vérifications, 29/31 scénarios au premier passage ; les 2 échecs étaient des attentes à réaligner (`11_evenements` : réactivation au lieu d’une nouvelle demande) ou indépendants de D-027 (`27_fuseaux_horaires` : fenêtre de dates sans lendemain de changement d’heure le 12/10), corrigés puis 22/0 et 24/0. Migration `20261012000000_imprevu_etats_et_actions.sql` et change packet `supabase/changements/D-027-01/` (niveau 2) préparés et répétés en local ; à exécuter **après** R2-01 et D-023c-01 (ordre des migrations testé ; appliqués selon leurs reçus).

**Ordre de livraison (12/10) : l’app du lot 1 d’abord, la base ensuite.** Aucune fenêtre où la base pourrait réactiver la demande d’une personne sans compte sans que l’app publiée propose « Renvoyer le message à … ». L’app du lot 1 est compatible avec la base sans D-027 (`message_a_renvoyer` absent lu comme `false`, `marquer_message_renvoye()` jamais appelé) : scénarios E2E de l’imprévu rejoués le 12/10 avec cette app sur une base sans la migration D-027 : 13 scénarios (parcours principal, demandes, acceptation et clôture, première acceptation, inviter et demander, ajout pendant l’imprévu, désistement, même personne des deux côtés, indisponibilité spontanée, conversations, annulations, confidentialité des numéros) tous verts ; seul `09b` échoue, comme attendu, car il vérifie le comportement serveur de D-027. Ordre : (1) app du lot 1 publiée (gh-pages, niveau 1, Go à part), commit source = tête de la branche `claude/sweet-einstein-ngufz2` au moment du Go ; (2) vérification de l’app publiée et délai de rechargement des appareils (service worker) ; (3) Go puis exécution de `D-027-01` ; (4) `verifier.sql`. Formulation de l’acceptation validée le 12/10 : « Kevin a accepté / Kevin sera là à ta place le jour J. ».

**Lot 2 (15/10) : implémenté côté serveur** (pas en production à cette date ; en production depuis le 20/10, voir plus bas). Migration `20261015000000_annulation_et_conversations.sql` ; change packet `D-027-02` (niveau 2) préparé, contrôlé (`--avant-go`) et répété en local, **sans validation** : aucun Go, aucune écriture en production. Lecture seule de la production le 15/10 : D-027-01 appliqué ; 0 Swend scellé puis annulé, 0 chat ; `annuler_swend()` et `annuler_si_double_absence()` en production dans une version antérieure à celle des migrations du dépôt (modifications des commits `5358f5d` et `7be0d90` absentes) : le paquet vérifie et restaure les versions de production. Le déclencheur du double remplacement **est présent** en production : `on_remplacant_selectionne` (`AFTER INSERT OR UPDATE OF selectionne ON public.remplacants FOR EACH ROW EXECUTE FUNCTION annuler_si_double_absence()`, actif), même définition que `trg_annuler_si_double_absence` du banc QA ; seul le nom diffère (écart historique admis depuis le 03/10, `qa/db/parite/declencheurs_admis.tsv`) — une première requête du 15/10 filtrait sur le nom QA et l’avait à tort fait paraître absent. Le lot 2 ne remplace que la fonction : `sauvegarde.sql` et `appliquer.sql` exigent ce déclencheur unique, actif et de cette définition (nom ignoré) ainsi que les déclencheurs de fermeture (2) et de protection de l’annulation (1), les sauvegardent, et `appliquer.sql` / `rollback.sql` vérifient qu’ils sont inchangés ; la répétition renomme les déclencheurs comme en production et vérifie le refus si le déclencheur est désactivé ou en double, le double remplacement par `on_remplacant_selectionne` après application (motif `double_remplacement`) et après rollback. QA du 15/10 : régression complète métier 1747/0 (SQL dont `99g_annulation_conversations` 79/0, suites `80`, `90`, `97`, `98`, `99`, `99b`, `99f` réalignées ; concurrence avec 3 nouvelles courses : double annulation, annulation et double remplacement, annulation et scellement Eliot–Kevin ; preuve conservée de la course avec et sans verrou par paire : 15/0 avec, 3/12 sans ; parité ; Dart sous 4 fuseaux) ; suites SQL sur une base où le lot 2 vient du paquet : 1063/0. E2E avec l’**app publiée (lot 1) sur une base avec le lot 2** (vérification V3 du paquet, fenêtre « base avant app ») : 26/31 au premier passage (722/5) ; les 5 échecs sont des effets attendus du lot 2 : texte d’annulation (`19`), titulaire remplacé refusé alors que l’app du lot 1 propose encore `Annuler le Swend` et n’affiche qu’un message générique (`20`, `23`), message d’une personne prévue accepté après l’annulation alors que l’app la présentait comme terminée (`22`), chat d’annulation du nouveau Swend annulé (`28`) ; scénarios réalignés, 5/5 verts (163 vérifications).

**Ordre de livraison du lot 2 : l’app du lot 3 d’abord, la base ensuite.** Avec l’app du lot 1, la base du lot 2 refuserait sans explication l’annulation d’un titulaire remplacé, réafficherait un Swend annulé à une personne sollicitée et accepterait des messages dans une conversation que l’app présente comme terminée. Exigences de compatibilité de l’app du lot 3 (avec et sans D-027-02) et vérifications V1 à V4 qui décident de l’ordre : `paquet.md` du paquet D-027-02, « Ordre d’exécution ».

**Lot 3 (15/10) : implémenté, pas publié.** App compatible avec la base actuelle (D-027-01) et avec D-027-02 ; `D-027-02` complété d’une 10e fonction (`envoyer_message_apres_swend()` : « Swend annulé · », titre « [Prénom] t’a écrit »), répété de nouveau, **sans validation**. QA, en distinguant suites complètes et reprises ciblées :
- **Suite complète, base avec D-027-02, commit `fbcd5b9`** (tutoiement des écrans compris) : métier 1811/0 (SQL, concurrence, parité, Dart sous 4 fuseaux), E2E 33/33 scénarios, 918/0.
- **Reprises ciblées, base avec D-027-02, commit `9d5ec6e`** (titre de push « t’a écrit », « Réessaie ») : métier complet 1811/0 (la migration avait changé), E2E `25` (54/0) et `31` (33/0).
- **Suite complète E2E, base sans D-027-02, commit `9d5ec6e`** : 31/33 scénarios, 802/2 ; les 2 échecs sont des attentes de test (`22` : accès perdu selon D-023a, « Cette conversation n’est plus accessible. » ; `28` : colonne `nature` absente), corrigées au commit `bfd89c1` et rejouées : `22` 13/0 et `28` 88/0 sans D-027-02, `22` 11/0 et `28` 88/0 avec D-027-02.
- Répétition du paquet et suites SQL sur une base issue du paquet : 1063/0 (`qa/preuves/2026-10-15_D-027-02_*`).
- Avant le lot 3 (3a seul, base avec D-027-02, commit `2f37ccb`) : E2E 30/32 au premier passage, 2 attentes de test corrigées (`09`, course dans `demander()`).

**App du lot 3 publiée le 20/10/2026** (Go d’Eliot, niveau 1) : textes validés le 20/10 appliqués (commit `bb75552` ; reprises ciblées : Dart 177/0, E2E `04`, `07`, `08`, `30` avec D-027-02 et `04` + parcours principal sans D-027-02, tous verts), `main` avancée par fast-forward à `bb75552`, build de production construite depuis une copie propre de ce commit et publiée sur `gh-pages` (commit `70fae74`, déploiement GitHub Pages n°92 `success` à 08:58 UTC), identifiant de build `a7e5fe0715e776007809589a3f4172f7`, contenu de `gh-pages` identique octet pour octet à la build. Vérification du chargement : impossible depuis l’environnement de travail (GitHub Pages, SDK Firebase et polices Google refusés par le proxy ; la build du lot 1 en service se comporte exactement pareil en local) — confirmé ensuite par Eliot dans un vrai navigateur (20/10 : « Un imprévu ? » se charge avec « Tu ne peux plus être là ? », la sélection des remplaçants et « Ajouter une personne »). Production relue en lecture seule après publication : D-027-01 appliqué, D-027-02 non appliqué. D-027-02 n’était pas encore exécuté au moment de la publication (empreinte inchangée `eaf20103686a…`, aucun `validation.json`). 

**Lot 2 en production depuis le 20/10/2026.** Contrôles avant le Go (lecture seule, 09:19 UTC) : préconditions de `paquet.md` toutes conformes (D-027-01 appliqué, D-027-02 absent, 10 empreintes, contraintes et déclencheurs d’origine dont `on_remplacant_selectionne`, 0 Swend scellé puis annulé avec conversation, sauvegarde pas encore faite), build publiée `a7e5fe07…` ; 2 Swends (1 scellé à venir le 17/11 sans demande, sélection ni message ; 1 en négociation), 0 demande, 0 conversation, 0 chat. Go d’Eliot enregistré (`validation.json`, `valide_par` : Eliot ; commit `9987a4a`). Exécution par la porte dans la session « Swend – écriture prod » : 09:28:35 → 09:28:39 UTC, `sauvegarde`, `appliquer`, `verifier` HTTP 201, `RESULTAT: SUCCES` (reçu `supabase/changements/D-027-02/journal/20261020T092835Z-appliquer.log`, commit `af120dc`, branche `recu/D-027-02`) ; `verifier.sql` : `chats_annulation` 0, `chats_apres_swend` 0 = `chats_sauvegardes` 0, `conversations_fermees` 0, `annulations_avec_motif` 0, `swends` 2 = `swends_sauvegardes` 2. Relecture en lecture seule après exécution (09:32 UTC) : `verifier.sql` identique ; assertions d’`appliquer.sql` rejouées toutes vraies (6 objets créés, 10 fonctions à l’empreinte testée dont `envoyer_message_apres_swend` « t’a écrit » / « Swend annulé · », règle du numéro D-024 identique à la sauvegarde, droits des fonctions remplacées inchangés, déclencheurs inchangés dont `on_remplacant_selectionne` actif, aucune donnée existante modifiée, droits des objets internes fermés à l’app, contraintes attendues) ; sauvegarde 16 / 2 / 0 lignes, schéma fermé à l’app. Jobs pg_cron après 09:28:39 UTC (relevé à 09:33 UTC) : `swend-rappels` 1/1 et `swend-gel-a-h` 1/1 (09:30), `swend-chat-apres` 5/5 (09:29 → 09:33), tous `succeeded`, aucun message d’échec ; aucun job déclenché manuellement. Ces résultats prouvent l’exécution et l’absence de régression des traitements planifiés ; **aucun parcours réel du lot 2 n’a encore été exercé** (0 annulation, 0 chat d’annulation, 0 conversation conservée ou fermée depuis) : tests humains à faire.

**Publication et transition (lot 3 puis D-027-02)** : ni contrôle de version, ni rechargement automatique, ni mesure d’adoption (Go du 15/10) ; aucun délai ne garantit qu’un appareil a rechargé l’app, et rien ne permet de prouver qu’aucune session du lot 1 ne reste ouverte. Procédure pour les quelques utilisateurs connus : (1) Go d’Eliot pour la publication de l’app (niveau 1), build publiée depuis le commit testé, `.last_build_id` relevé ; (2) fenêtre courte et annoncée, de préférence sans Swend scellé à venir avec une demande, une sélection ou un message ; (3) chacun recharge l’onglet ou ferme puis rouvre l’app installée et le confirme (seule l’app du lot 3 affiche « Tu ne peux plus être là ? ») ; (4) juste avant le Go du paquet, en lecture seule : préconditions de `paquet.md` (10 empreintes, D-027-02 absent, aucun Swend scellé puis annulé avec conversation), build publiée inchangée, état des Swends à venir ; (5) Go d’Eliot pour `D-027-02` et exécution par la porte ; (6) vérifications en lecture seule (jobs pg_cron), rechargement redemandé à toute personne non confirmée. Une session du lot 1 oubliée reste sans effet sur les données ni la confidentialité (V3) : confusion d’affichage seulement. Détail : `paquet.md` de D-027-02, « Ordre d’exécution ».

---

## R1 / R1b — Sécurité des notifications push

**Statut : Validée, techniquement close**  
**Date : 02/10/2026**

Lot de sécurité issu de l’audit de production du 02/10 (hors numérotation D- des décisions produit). Aucun changement de comportement pour l’app ni pour les utilisateurs.

### Décision
- **R1** : `public.notifier()` n’est plus exécutable par `PUBLIC`, `anon` ni `authenticated` (droits : `{postgres=X/postgres}`). Seules les fonctions serveur `SECURITY DEFINER` propriété de `postgres` (déclencheurs, moteurs planifiés) l’appellent.
- **R1b** : l’Edge Function `send-notification` n’accepte plus que les appels émis par `notifier()`, et seulement pour la notification exacte préparée. Mécanisme : un jeton à usage unique, lié au contenu (`profile_id`, `title`, `body`, `data`), valable 15 minutes, consommé de façon atomique par `consommer_jeton_notification()` avant tout traitement. En base, seules les empreintes SHA-256 du jeton et du contenu sont stockées (`notification_jetons`), jamais le jeton brut. Tout autre appel : 403 `non_autorise`, sans appel FCM.
- **R1b** : `notifier()` n’envoie plus la clé `service_role` via pg_net (elle passait en clair dans `net.http_request_queue`, lisible avec un accès en lecture seule). Elle utilise la clé anon publique pour la passerelle et ne lit plus le Vault.

### Raison
Avant R1, n’importe quel compte pouvait appeler `notifier()` ; avant R1b, n’importe qui pouvait appeler `send-notification` avec la clé anon publique (notification arbitraire vers n’importe quel profil, suppression de ses appareils), et la clé `service_role` transitait par la file pg_net.

### Mise en production
- R1 : exécuté en production le 02/10/2026 par Kevin, avant la mise en place des change packets, puis vérifié en lecture seule.
- R1b : change packet `supabase/changements/R1b-01/` (niveau 1, empreinte `85819e728b92`, `Go R1b-01` donné par Eliot), exécuté le 02/10/2026 par la porte d’écriture (`RESULTAT: SUCCES` à 17:58:35 UTC). Reçu conservé dans le dépôt : `supabase/changements/R1b-01/journal/20261002T175829Z-appliquer.log`.
- Vérifié en production le 02/10/2026 (lecture seule) : appel légitime de `notifier()` → 200 (`envoyes: 1`) ; appels directs anon sans jeton et avec jeton inventé (requêtes 50 et 51) → 403 `non_autorise` ; aucun jeton en attente ; `send-notification` `ACTIVE`, version 5, `verify_jwt = true` ; comparaison du catalogue avant / après : seuls les objets R1b et le corps de `notifier()` ont changé ; jobs pg_cron tous `succeeded` depuis le déploiement, aucun échec.
- Garde-fous de production : `scripts/tests/test_garde_prod.sh` 135/135 le 02/10.

### Reste à faire (hors R1 / R1b)
- Décisions humaines (niveau 3) : supprimer le secret Vault `service_role_key_notifications`, devenu inutile hors rollback de R1b-01 ; décider d’une rotation de la clé `service_role`.
- Banc QA : sa doublure de `notifier()` n’est pas réalignée sur R1b (lot à part).
- Dette d’outillage : `.claude/hooks/garde_prod.py` peut bloquer à tort certaines commandes locales (faux positif) ; non corrigé pour l’instant.

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
