# Tests humains — « En cas d'imprévu » (D-027, lots 1 à 3 et D-027-03)

Révisé le 20/10/2026. En production, avec de vrais comptes et l'app en
service (build `d324b42a…`, rechargée sur chaque appareil). **Ne modifier
aucune heure ni aucune donnée en base, n'arrêter aucun job.** Les textes
attendus ci-dessous sont ceux du code ; un écart est à noter tel quel.

## Avant la première séance (préparation, rien à créer dans l'app)

| Rôle | Compte | Appareil | À préparer |
|---|---|---|---|
| Eliot | compte d'Eliot | téléphone d'Eliot | app rechargée, notifications autorisées |
| Kevin | compte de Kevin | téléphone de Kevin | app rechargée, notifications autorisées |
| Test 1 | compte de test (numéro de mobile qui lui est propre) | ordinateur, profil de navigateur n°1 | connecté, notifications autorisées |
| Test 2 | compte de test (autre numéro) | ordinateur, profil de navigateur n°2 | connecté, notifications autorisées |
| N | aucun compte : un numéro de mobile de l'équipe, jamais inscrit | — | séance 2 seulement ; aucun message ne lui sera envoyé |

Règles pour toutes les séances :
- **Swend réel du 17/11** : ne jamais l'ouvrir pour tester, ni « Un imprévu ? »,
  ni annulation. Toujours ouvrir le Swend de test indiqué.
- **Un seul Swend en cours par paire de titulaires** (négociation avec une
  date à venir, ou scellé et pas encore passé). Au 20/10, la paire
  Eliot–Kevin n'en a aucun (relu en lecture seule). En début de séance,
  vérifier dans « Mes Swends » d'Eliot qu'aucun « Swend avec Kevin » n'est
  à venir. S'il y en a un : ne pas en créer ; Eliot crée le Swend de test
  avec Test 1 à la place de Kevin, et Kevin tient le rôle de Test 1.
- Swends de test : date à au moins 15 jours (le calendrier commence à la
  première date possible), n'importe quel restaurant, **aucune
  réservation** (ils apparaissent dans le suivi interne des réservations ;
  à ignorer). Chaque parcours se termine Swend annulé : rien ne reste en
  cours, aucun rappel ne partira, la paire est libérée.
- Conversations d'imprévu (titulaire ↔ personne de confiance) : **jamais de
  notification de message**, on vérifie dans l'app. « [Prénom] t'a écrit »
  ne concerne que le chat d'annulation (et le chat après le Swend).

## Séance 1 — parcours essentiels (≈ 32 min, Eliot et Kevin)

Un seul Swend de test, **S1 : Eliot ↔ Kevin**, personnes de confiance
d'Eliot : Test 1 et Test 2. Les étapes 1.1 à 1.6 sont **enchaînées dans
l'ordre** (chacune part de l'état laissé par la précédente).

**1.1 Création et scellement (7 min)** — Eliot, Kevin.
État initial : aucun Swend Eliot–Kevin en cours.
1. Eliot : `Créer un Swend` → Kevin (prénom, nom, numéro) → « Kevin est déjà sur Swend » → `Suivant`.
2. Eliot, étape « Où et quand » : lire « D’autres restaurants te seront bientôt proposés. Tu peux nous en suggérer ici. » (« ici » est un lien) ; ajouter une date à au moins 15 jours → `Suivant`.
3. Eliot : ajouter Test 1 et Test 2 (« … est déjà sur Swend ») → `Envoyer le Swend`.
4. Kevin : `Mes Swends` → carte « À toi de répondre » → choisir la date, ne pas ajouter de personne → sceller.

Résultat : S1 scellé chez les deux.

**1.2 Imprévu, deux demandes (4 min)** — Eliot, Test 1, Test 2, Kevin.
1. Eliot : S1 → `Un imprévu ?` → « Tu ne peux plus être là ? » et « Si personne n’a accepté avant [jour] à [heure du Swend − 3 h], le Swend sera annulé. »
2. Eliot : cocher Test 1 et Test 2 → `Envoyer 2 demandes` → confirmer.

Résultat : Eliot « C’est envoyé. » ; Test 1 et Test 2 : notification « On a besoin de toi » et carte « UNE DEMANDE T'ATTEND » à l’accueil ; Kevin : aucune notification, aucun nom des personnes d’Eliot sur sa fiche.

**1.3 Première acceptation (3 min)** — Test 1, Eliot, Test 2, Kevin.
1. Test 1 : accueil → `Répondre à la demande` → `Voir la demande et répondre` → `Accepter`.

Résultat : Eliot : notification « Test 1 a accepté / Test 1 sera là à ta place le jour J. », écran « Test 1 a accepté. », plus aucune action d’imprévu ni d’annulation ; Test 2 : « Plus besoin de répondre / La place a été prise pour ce Swend. » ; Kevin : rien.
Ne rien ajouter ni relancer après l’acceptation.

**1.4 Désistement avant H-3 (3 min)** — Test 1, Eliot, Test 2.
1. Test 1 : S1 → `Je ne peux finalement plus venir` → confirmer.

Résultat : Eliot : « Test 1 ne peut finalement plus venir / Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire. » ; Test 2 : « Ta réponse est finalement attendue / La place est à nouveau disponible pour ce Swend. » ; Kevin : rien.

**1.5 Refus, dernier recours, annulation (6 min)** — Test 2, Eliot, Kevin.
1. Test 2 : accueil → `Répondre à la demande` → `Voir la demande et répondre` → `Refuser`.
2. Eliot : notification « Personne n’est disponible pour l’instant / Tu peux solliciter quelqu’un d’autre. » ; S1 → `Un imprévu ?` → « Personne n’a pu prendre ta place. » → `Je n’ai personne d’autre` → « Tu n’as personne d’autre ? » → `Annuler le Swend` → « Annuler ce Swend ? » → confirmer.

Résultat : Kevin : « Le Swend est annulé / Eliot ne pourra finalement pas être là. », S1 « Ton Swend avec Eliot est annulé. » ; Test 1 et Test 2 : aucune notification (refus et désistement).

**1.6 Après l’annulation (6 min)** — Kevin, Eliot, Test 2.
1. Kevin : S1 → bloc « APRÈS L’ANNULATION » → `Discuter` → écrire un message.
2. Eliot : notification « Kevin t’a écrit / Swend annulé · [restaurant] » → répondre ; Kevin reçoit « Eliot t’a écrit ».
3. Eliot : S1 → `Reprendre une conversation` → Test 2 → écrire.
4. Test 2 : S1 reste dans son historique (« Ce Swend a été annulé. ») ; le message d’Eliot y est, **sans notification** ; répondre.

Résultat : chat d’annulation entre Eliot et Kevin seulement ; conversations Eliot–Test 1 et Eliot–Test 2 conservées et écrivables, sans notification de message ; Kevin ne voit jamais Test 1 ni Test 2.
Fin de séance : S1 annulé, rien en cours.

## Séance 2 — autres parcours (indépendants)

Chacun crée **son propre Swend de test** (création et scellement comme en
1.1, au moins 15 jours) et se termine annulé. Ordre libre, sauf 2.4 qui
réutilise la conversation Eliot–Test 2 de la séance 1.

**2.1 Personne sans compte, puis « Je peux finalement venir »** — Eliot, Kevin, Test 2.
Swend S2 : Eliot ↔ Kevin ; personnes d’Eliot : N et Test 2.
1. Eliot : `Un imprévu ?` → cocher N → `Demander à N` → confirmer → « Demande envoyée à N » et « N n’a pas encore de compte Swend : envoie-lui un message pour lui expliquer… » → `Plus tard` (ne rien envoyer).
2. Eliot : `Solliciter quelqu’un d’autre` → Test 2 → envoyer.
3. Eliot : `Je peux finalement venir` → confirmer → « C’est noté : tu seras là. »

Résultat : Test 2 : « Plus besoin de répondre / Eliot pourra finalement être là pour ce Swend. » ; Kevin : rien.
Fin : Kevin (sans personne de confiance) : `Un imprévu ?` → `Je n’ai personne d’autre` → `Annuler le Swend`.

**2.2 Titulaire remplacé, l’autre titulaire annule** — Eliot, Kevin, Test 1.
Swend S3 : Eliot ↔ Kevin ; personne d’Eliot : Test 1.
1. Eliot demande à Test 1 ; Test 1 accepte.
2. Eliot : vérifier qu’aucune action d’annulation n’est proposée.
3. Kevin : `Un imprévu ?` → `Je n’ai personne d’autre` → `Annuler le Swend` → confirmer.

Résultat : Eliot : « Le Swend est annulé / Kevin ne pourra finalement pas être là. » ; Test 1 : « Le Swend est annulé / Tu n’auras finalement pas besoin de prendre la place d’Eliot. », S3 « Ce Swend a été annulé. » avec `Écrire à Eliot`.

**2.3 Double remplacement** — Eliot, Kevin, Test 1, Test 2.
Swend S4 : Eliot ↔ Kevin ; personne d’Eliot : Test 1 ; personne de Kevin : Test 2.
1. Eliot demande à Test 1 ; Test 1 accepte.
2. Kevin demande à Test 2 ; Test 2 accepte.

Résultat : Swend annulé aussitôt ; Eliot : « Le Swend est annulé. / Ni toi ni Kevin ne pourrez finalement être là. » (Kevin : symétrique) ; Test 1 et Test 2 : « Tu n’auras finalement pas besoin de prendre la place de … ».

**2.4 Fermeture par un nouveau Swend** — Eliot, Test 2 (après la séance 1).
Swend S5 : Eliot ↔ Test 2, sans personne de confiance.
1. Eliot crée S5 avec Test 2 ; Test 2 le scelle.
2. Eliot et Test 2 : ouvrir leur conversation de S1.

Résultat : « Un nouveau Swend a été scellé entre vous. / Cette conversation est désormais fermée. », bandeau « Cette conversation est fermée. Elle reste consultable. », plus de saisie ; la conversation Eliot–Test 1 n’est pas touchée.
Fin : Eliot : S5 → `Un imprévu ?` → `Je n’ai personne d’autre` → `Annuler le Swend`.

**Observable sans rien faire** (Swend réel du 17/11, s’il a lieu
normalement) : rappels le 10/11, le 14/11 et le 16/11 à 18h00 et le
17/11 à 16h00 ; plus aucune action d’imprévu à 19h00 ; chat « Alors, ce
Swend ? » à 22h00, puis « [Prénom] t’a écrit » pour ses messages. Les
rappels J-7 et J-1 sont encore au vouvoiement (lot 4).

## Hors production — environnement de test nécessaire

Ces cas demandent un Swend à moins de 3 heures ou une panne des jobs : ne
pas les provoquer en production. Couverts par le banc QA local (suite
`99h`, courses de `qa/metier/concurrence.sh`, E2E `21` et `32`) ; un test
humain demanderait un projet Supabase de test (à décider).

| Cas | Résultat attendu |
|---|---|
| Recherche non résolue à H-3 | Annulation dans la minute ; titulaire : « Le Swend est annulé / Personne n’a pu prendre ta place à temps. » ; personnes en attente : « Tu n’as plus besoin de répondre. » |
| Acceptation tentée à partir de H-3 | « Il est trop tard : à partir de 3 heures avant le Swend, on ne peut plus chercher ni accepter de remplaçant. » |
| Nouvel imprévu après H-3 | « Tu ne peux plus être là ? / À partir de 3 heures avant le Swend… » → `Annuler le Swend` |
| Désistement du remplaçant après H-3 | Confirmation « …personne d’autre ne pourra prendre la place d’Eliot : le Swend sera annulé. » ; annulation immédiate, aucune réactivation |
| Panne des jobs entre H-3 et H, reprise après H | Annulation au premier traitement réussi, jamais « La demande n’est plus d’actualité » ni « Alors, ce Swend ? » |
