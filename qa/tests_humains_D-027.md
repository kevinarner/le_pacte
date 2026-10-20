# Tests humains — « En cas d'imprévu » (D-027, lots 1 à 3 et D-027-03)

Préparé le 20/10/2026. App en service : build `0ef9f22b…` (D-027-03) ou
suivante. À faire en production, avec de vrais comptes, **sans modifier
aucune heure ni aucune donnée en base**.

## Rôles nécessaires

| Rôle | Qui | Compte |
|---|---|---|
| A — titulaire qui a l'imprévu | Eliot | oui |
| B — autre titulaire | Kevin | oui |
| C — personne de confiance de A | compte de test n°1 (téléphone distinct) | oui |
| D — personne de confiance de A | compte de test n°2 (téléphone distinct) | oui |
| E — personne de confiance de A | un numéro réel, sans compte | non |

Il faut donc 2 comptes de plus qu'Eliot et Kevin (un numéro par compte).
Pour les parcours « autre côté » (7, 8), B ajoute aussi C ou D comme
personne de confiance de son côté.

Préparation : créer des **Swends de test dédiés** entre A et B, à au moins
15 jours (délai minimum), choisir un restaurant sans réserver (une
annulation apparaît dans le suivi interne « Annuler la réservation au
restaurant »). Ne pas utiliser le Swend réel du 17/11 pour les annulations.

## Partie 1 — parcours réalisables normalement (Swend à plus de 3 h)

| # | Parcours | Résultat attendu |
|---|---|---|
| 1 | A crée un Swend avec B, ajoute C, D, E. B répond et choisit la date. | Création : « D’autres restaurants te seront bientôt proposés. Tu peux nous en suggérer ici. » (lien sur « ici ») ; E : « E n’a pas encore de compte Swend. » ; B : « À toi de répondre » ; date à moins de 15 jours refusée : « Choisis une date au moins 15 jours à l’avance. » ; Swend scellé. |
| 2 | A : « Un imprévu ? », sélectionne C et D, envoie. | « Si personne n’a accepté avant [jour] à [H-3], le Swend sera annulé. » (H-3 juste : 19h00 → 16h00) ; « C’est envoyé. » ; C et D reçoivent la demande ; B ne voit rien. |
| 3 | C accepte. | A : « C a accepté. / C sera là à ta place le jour J. » ; la demande de D se ferme ; B voit seulement que le Swend a lieu, jamais C ni D. |
| 4 | Nouveau Swend : A demande à E (sans compte). | « Demande envoyée à E » puis « E n’a pas encore de compte Swend : envoie-lui un message… » ; `Envoyer le message` ouvre le partage. |
| 5 | Nouveau Swend : A demande à C, puis « Je peux finalement venir ». | Confirmation, retour à la fiche ; C est prévenu qu’il n’a plus besoin de répondre ; plus d’imprévu. |
| 6 | Nouveau Swend : C accepte, puis « Je ne peux finalement plus venir » (bien avant H-3). | A : « C ne peut finalement plus venir. » ; les demandes en attente se rouvrent (D : « Ta réponse est finalement attendue »). |
| 7 | Nouveau Swend : C et D refusent ; A : « Je n’ai personne d’autre » → `Annuler le Swend`. | « Tu n’as personne d’autre ? », puis « Annuler ce Swend ? » ; B : « Le Swend est annulé / Eliot ne pourra finalement pas être là. » ; chat d’annulation A–B (« APRÈS L’ANNULATION ») ; les conversations A–C et A–D restent écrivables ; C et D retrouvent le Swend dans leur historique. |
| 8 | Titulaire remplacé (A remplacé par C) : A n’a plus de bouton d’annulation ; B annule. | C : « Tu n’auras finalement pas besoin de prendre la place d’Eliot. » ; aucune fuite des personnes de A vers B. |
| 9 | Double remplacement : A remplacé par C, B remplacé par sa personne de confiance. | Swend annulé : « Ni toi ni [autre] ne pourrez finalement être là. » |
| 10 | Après le 7 : A et C scellent un nouveau Swend entre eux. | Conversation A–C : « Un nouveau Swend a été scellé entre vous. / Cette conversation est désormais fermée. » ; lecture seule. |
| 11 | Pendant les parcours : messages dans les conversations et le chat d’annulation. | Push « [Prénom] t’a écrit » ; cartes d’accueil au tutoiement. |

Observables sans rien faire, sur le Swend du 17/11 s’il a lieu
normalement : rappels J-7 (10/11), J-3 (14/11), J-1 (16/11) à 18h00 et du
Jour J à 16h00 ; à 19h00, plus aucune action d’imprévu ; à 22h00, chat
« Alors, ce Swend ? ». Les rappels J-7 et J-1 sont encore au vouvoiement
(lot 4).

## Partie 2 — cas qui demandent un environnement de test

Non réalisables en production sans attendre un vrai Swend à H-3 ou
provoquer une panne : **ne pas déplacer de date ni arrêter de job en
production.** Couverts aujourd’hui par le banc QA (suite `99h`, courses de
`qa/metier/concurrence.sh`, E2E `21` et `32`) ; un test humain demande un
projet Supabase de test (à décider).

| Cas | Résultat attendu |
|---|---|
| Recherche non résolue à H-3 | Swend annulé dans la minute ; A : « Le Swend est annulé / Personne n’a pu prendre ta place à temps. » ; B prévenu ; les personnes en attente : « Tu n’as plus besoin de répondre. » |
| Acceptation tentée à partir de H-3 | « Il est trop tard : à partir de 3 heures avant le Swend, on ne peut plus chercher ni accepter de remplaçant. » |
| Nouvel imprévu après H-3 | « Tu ne peux plus être là ? / À partir de 3 heures avant le Swend… » → `Annuler le Swend` |
| Désistement du remplaçant après H-3 | Confirmation « …personne d’autre ne pourra prendre la place d’Eliot : le Swend sera annulé. » ; annulation immédiate, aucune réactivation |
| Panne des jobs entre H-3 et H, reprise après H | Au premier traitement réussi : annulation (jamais « La demande n’est plus d’actualité » ni « Alors, ce Swend ? »), push d’annulation même tardives |
| Swend maintenu à H puis chat après le Swend | Plus d’action à H ; « Alors, ce Swend ? » à l’heure prévue |
