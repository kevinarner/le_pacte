# D-023c-01

Niveau : 1 — préparé le 03/10/2026. Empreinte : donnée par
`scripts/paquet_controler.sh D-023c-01 --avant-go`.

## Objectif

Mettre en production le côté serveur de **D-023c** (« Faire un nouveau
Swend » et fermeture du chat après le Swend), décrit dans `DECISIONS.md` et
`PRODUCT_RULES.md` §3.7 :

1. **Fermeture au scellement, côté base.** Dès qu'un Swend devient scellé
   (`scelle_le` passe de NULL à une date, à l'insertion ou à la
   modification, quel que soit le point d'entrée), chaque chat après le
   Swend déjà ouvert où ses **deux** titulaires sont participants ensemble
   est fermé définitivement (`ferme_le`, `motif_fermeture = 'nouveau_swend'`),
   avec **un seul** message système : « Un nouveau Swend a été scellé. / Ce
   chat est désormais fermé pour préserver le silence. ». Aucune push. Une
   invitation ou une négociation ne ferme rien ; une annulation ultérieure ne
   rouvre rien.
2. **Chat pas encore ouvert.** Un Swend scellé plus ancien (date antérieure à
   celle du nouveau), sans chat, dont les deux titulaires du nouveau Swend
   sont participants potentiels, ne s'ouvrira jamais (table interne
   `chats_apres_swend_jamais_ouverts`). Participants potentiels : une seule
   fonction, `participants_potentiels_chat_apres_swend()`, utilisée par le
   moteur d'ouverture ET par la fermeture (logique inchangée du moteur : les
   deux titulaires et le remplaçant sélectionné non retiré).
3. **Un Swend actif par paire** (`swend_actif_entre()`, interne) et deux
   fonctions pour l'app, depuis un chat ouvert seulement :
   `options_nouveau_swend(chat)` (autres participants, prénom, « Swend déjà
   en cours ») et `creer_swend_depuis_chat(…)` (personne désignée par son
   identifiant de participant ; numéro recopié par la base, jamais renvoyé,
   D-024 ; D-025 appliqué ; personnes de confiance dans la même transaction).

Aucune donnée existante n'est modifiée par l'application : en production,
0 chat (le seul Swend scellé, le 17/11, n'a pas encore eu lieu).

## Fichiers concernés

Artefacts : `appliquer.sql` (préconditions, migration
`supabase/migrations/20261003010000_nouveau_swend.sql` sections 1 à 6 en
copie exacte, assertions ; une transaction), `verifier.sql` (lecture seule),
`rollback.sql`.

Objets de production :
- créés : table `public.chats_apres_swend_jamais_ouverts` (RLS activée,
  aucun droit pour `public`, `anon`, `authenticated`) ; fonctions
  `participants_potentiels_chat_apres_swend(uuid)`,
  `fermer_chats_apres_nouveau_swend()` (déclencheur, SECURITY DEFINER),
  `swend_actif_entre(uuid, uuid)` (internes, non exécutables par l'app),
  `options_nouveau_swend(uuid)` et
  `creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb)` (SECURITY
  DEFINER, `authenticated` seulement) ; déclencheurs AFTER sur `pactes` :
  `trg_fermer_chats_nouveau_swend_insert` (`WHEN new.scelle_le IS NOT
  NULL`) et `trg_fermer_chats_nouveau_swend_update` (`WHEN old.scelle_le IS
  NULL AND new.scelle_le IS NOT NULL`), même forme que
  `trg_creer_suivi_reservation_*` ;
- remplacé : `ouvrir_chats_apres_swend(timestamptz)` (mêmes droits ;
  participants lus par la fonction commune ; Swends « jamais ouverts »
  ignorés, avant et après le verrou du Swend).

Aucune politique RLS existante, aucune colonne, aucune donnée, aucune Edge
Function ni planification modifiées. Le job `swend-chat-apres` continue
d'appeler le même moteur.

Niveau 1 : changement réversible (rollback exact, répété), sans donnée
réelle, sans DDL destructif, sans politique RLS modifiée. La seule table
créée est interne et fermée, comme `notification_jetons` (R1b-01, niveau 1).

## Préconditions

Vérifiées en lecture seule le 03/10/2026 (endpoint `…/read-only`) :

```sql
select (select count(*) from public.chats_apres_swend) as chats,                 -- 0
       (select count(*) from public.messages_apres_swend where genre = 'systeme'), -- 0
       (select count(*) from public.pactes) as swends,                           -- 2
       (select count(*) from public.pactes where scelle_le is not null),          -- 1
       to_regclass('public.chats_apres_swend_jamais_ouverts') is null,            -- true
       md5(prosrc) du moteur ouvrir_chats_apres_swend                             -- 77ab4ee095fefb3a47f11a722ec9adc9
```

Aucun homonyme des nouveaux objets ; R2 appliqué
(`trg_verrou_zz_dates_swend` actif) ; job `swend-chat-apres` actif ; le
moteur en production est identique à la migration D-023b (corps comparé).

`appliquer.sql` revérifie tout avant d'écrire et annule tout sinon :
objets D-023b et R2 présents, corps du moteur inchangé (md5 ci-dessus),
D-023c pas encore appliqué.

Tests (banc QA, 03/10/2026) : suite `qa/metier/sql/99e_nouveau_swend.sql`
(56 vérifications), concurrence (3 cas D-023c : scellements simultanés,
moteur et scellement simultanés, créations simultanées), scénario E2E
`28_nouveau_swend` (82 vérifications), régression complète (voir
`DECISIONS.md`, D-023c).

Répétition sur une base locale reproduisant la production avant D-023c
(toutes les migrations sauf celle-ci ; même md5 du moteur) :
`appliquer.sql` OK ; seconde exécution refusée ; `verifier.sql` OK ;
`rollback.sql` OK (md5 du moteur d'origine retrouvé, objets supprimés),
puis `verifier.sql` refuse ; rollback sans D-023c refusé ; réapplication
OK ; toutes les suites SQL (860/0) et la concurrence (12/12) ensuite ;
rollback refusé une fois un chat marqué « jamais ouvert ».

## Impact attendu

- Immédiat : aucun changement visible. Aucune donnée modifiée.
- Ensuite, à chaque scellement : fermeture des chats concernés et message
  système (aucun chat en production aujourd'hui).
- Les fonctions de l'app ne servent qu'à la nouvelle version de l'app
  (« Faire un nouveau Swend »). L'app actuelle ne les appelle pas ; elle
  affiche déjà un chat fermé en lecture seule (D-023b).
- Durée : une transaction courte (création de fonctions et de 2
  déclencheurs ; verrou bref sur `pactes`).

## Vérifications après exécution

`verifier.sql` (lecture seule) ne lève aucune erreur et affiche :
`declencheurs_fermeture = 2`, `fonctions_d023c = 5`, `chats = 0`,
`chats_fermes = 0`, `messages_systeme = 0`, `chats_jamais_ouverts = 0`,
`swends = 2` (ou plus si des Swends ont été créés entre-temps),
`job_chat_actif = 1`.

Session de travail, en lecture seule ensuite : exécutions de
`swend-chat-apres` toujours `succeeded` ; aucune anomalie dans
`anomalies_chat_apres_swend`.

## Rollback

Quand : régression constatée sur le scellement ou l'ouverture des chats.
Ordre : d'abord remettre l'app précédente (gh-pages), qui n'appelle pas les
nouvelles fonctions, puis `scripts/prod_ecrire.sh D-023c-01 <empreinte>
--rollback`.

Effet : déclencheurs et fonctions D-023c supprimés, moteur d'ouverture remis
à l'identique (définition relue en production le 03/10/2026, md5 du corps
contrôlé), table `chats_apres_swend_jamais_ouverts` supprimée.

Ne rétablit pas : les chats déjà fermés restent fermés avec leur message
système (D-023c : jamais de réouverture ; l'app précédente les affiche en
lecture seule) ; les Swends créés depuis un chat restent des Swends
ordinaires. Refusé (rien n'est modifié) si un chat a déjà été marqué
« jamais ouvert » : le moteur d'origine l'ouvrirait, décision humaine.

## Sauvegardes

Aucune : niveau 1, aucune donnée existante modifiée ni supprimée par
`appliquer.sql` (assertion finale : aucun chat fermé, aucun message
système, aucun chat marqué). La définition d'origine du moteur, seul objet
remplacé, est conservée dans `rollback.sql`.

## Ordre d'exécution (production puis app)

1. Go sur ce paquet selon la gouvernance en vigueur (`CLAUDE.md`), puis
   exécution par la porte.
2. `verifier.sql`, puis vérification en lecture seule.
3. Ensuite seulement : déploiement de l'app D-023c (gh-pages, niveau 1, Go
   à part). L'app ne doit pas précéder la migration : « Faire un nouveau
   Swend » appellerait des fonctions absentes (message d'erreur, rien de
   cassé).
