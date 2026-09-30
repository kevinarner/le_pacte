# Banc QA de Swend

Rejouer automatiquement les scénarios Eliot / David / Kevin / Sylvain après
chaque modification, sur une pile **100 % locale**, jamais sur la production.

| Niveau | Commande | Contenu | Durée indicative |
|---|---|---|---|
| Métier | `qa/run_metier.sh` | règles serveur (SQL) + logique Dart, sans navigateur | ~10 s |
| Smoke | `qa/run_smoke.sh` | le parcours principal en navigateur (17 étapes) | ~1 min |
| Complet | `qa/run_full.sh` | métier + tous les scénarios E2E (25) | ~28 min |
| Un scénario | `qa/run_scenario.sh <nom>` | un scénario E2E (nom complet ou partiel) | 30 s – 1 min 30 |

Chaque commande démarre la pile et reconstruit l'app QA si nécessaire, puis
affiche un rapport `PASS` / `FAIL` avec un résumé et la durée. Code de
sortie : 0 si tout passe, 1 sinon.

## Prérequis (une seule fois)

- Postgres 16 (binaires `initdb`, `pg_ctl`, `psql` ; détectés dans
  `/usr/lib/postgresql/*/bin`, ou `PG_BIN=...`).
- Node 18+ et Flutter (le même que pour l'app).
- Chromium : celui de Playwright (`/opt/pw-browsers`), ou `QA_CHROMIUM=/chemin/vers/chrome`.

```bash
qa/stack.sh setup     # npm install (playwright-core, ws) + PostgREST 12.2.3 (somme SHA-256 vérifiée)
```

## Utilisation courante

```bash
qa/run_metier.sh              # après toute modification SQL ou Dart
qa/run_smoke.sh               # après chaque lot
qa/run_full.sh                # avant une livraison
qa/run_full.sh --e2e          # E2E seulement
qa/run_scenario.sh --liste    # liste des scénarios
qa/run_scenario.sh desistement
qa/run_metier.sh sql          # (ou dart) une partie des tests métier
```

Pile locale :

```bash
qa/stack.sh start | stop | status | logs
qa/stack.sh reset             # reconstruit la base E2E (schéma + migrations + fixtures)
                              # (automatique au démarrage si une migration, la réplique
                              #  ou les fixtures ont changé)
qa/app/construire_app.sh --forcer   # reconstruit l'app QA même si rien n'a changé
```

## Architecture

```
qa/
  config.env               ports, bases, secret JWT local (aucun secret réel)
  lib/garde_fou.sh         protection absolue de la production (voir plus bas)
  stack.sh                 Postgres + PostgREST + faux Supabase + serveur de l'app
  stack/faux_supabase.mjs  /auth/v1 (4 comptes fixes), /rest/v1 → PostgREST (RLS réelle),
                           /realtime/v1 (changements poussés en direct, sous RLS)
  db/replica/              schéma de production d'avant les migrations (reconstruit)
  db/construire_base.sh    réplique + supabase/migrations/*.sql + fixtures
  db/fixtures.sql          états de départ déterministes : qa.charger('<état>')
  app/construire_app.sh    copie isolée de l'app pointée sur la pile locale, build web
  metier/sql/*.sql         tests SQL (verifier(...) → table test_resultats)
  metier/concurrence.sh    actions réellement simultanées (verrous, courses)
  metier/rattrapage.sh     migration téléphone sur des données existantes "sales"
  e2e/run.mjs              lanceur E2E (suites smoke / full, --scenario, --liste)
  e2e/lib/                 acteur (session navigateur isolée), actions métier,
                           vérifications, confidentialité de David, rapport,
                           numeros.mjs (numéros reçus dans les réponses réseau, D-024)
  e2e/scenarios/*.mjs      un fichier par scénario
  artifacts/               rapports et artefacts d'échec (non versionné)
```

Les migrations SQL de production sont versionnées dans `supabase/migrations/`
(ordre = nom de fichier). Le banc les applique toutes sur une base neuve, puis
les **rejoue** pour vérifier qu'elles sont idempotentes.

### Données de test

Comptes (mot de passe : `QA_MOT_DE_PASSE` dans `config.env`) :

| Compte | Email | Téléphone du profil |
|---|---|---|
| Eliot Martin | eliot@swend.test | 06 01 02 03 04 |
| David Schlang | david@swend.test | +33 6 02 03 04 05 |
| Kevin Arner | kevin@swend.test | 0670419277 |
| Sylvain Landiech | sylvain@swend.test | 06 55 44 33 22 |

Contacts sans compte : Tom Petit (07 11 22 33 44), Léo Blanc, Nina Roy.

États de départ (`qa.charger(...)`, rechargés avant chaque scénario) :

- `comptes` : les 4 comptes, aucun Swend ;
- `scelle` : Swend scellé Eliot / David dans 30 jours ; côté Eliot : Kevin,
  Sylvain, Tom ; côté David : Léo, Nina ;
- `scelle_kevin_deux_cotes` : `scelle` + Kevin aussi côté David ;
- `scelle_double` : côté Eliot : Kevin, Tom ; côté David : Sylvain, Léo.

Identifiants fixes (voir `fixtures.sql` et `e2e/lib/donnees.mjs` → `FICHES`).

## Ajouter un scénario E2E

Créer `qa/e2e/scenarios/NN_nom.mjs` :

```js
import * as A from '../lib/actions.mjs';
import { demande, FICHES } from '../lib/donnees.mjs';
import { photoDavid, verifierDavidNeVoitRien } from '../lib/confidentialite.mjs';

export default {
  nom: 'mon_scenario',
  titre: 'Ce que le scénario garantit',
  suites: ['full'],            // ou ['smoke', 'full']
  fixture: 'scelle',           // état de départ
  async executer(ex) {
    const eliot = await ex.eliot();                 // session isolée, déjà connectée
    ex.memo.david = await photoDavid(ex);           // ce que David voit avant
    await ex.etape('Eliot demande à Kevin', async () => {
      await A.ouvrirImprevu(eliot);
      await A.demander(eliot, 'Kevin Arner');
      await ex.verifier('demande envoyée', () => demande(FICHES.kevin) === 'envoyee|f');
      await ex.verifierTexte(eliot, /Kevin Arner\s+En attente/, 'badge "En attente"');
    });
    await ex.etape('David ne voit rien', () => verifierDavidNeVoitRien(ex, ex.memo.david));
  },
};
```

Règles :

- interagir comme un utilisateur (libellés visibles de l'app, `e2e/lib/actions.mjs`) ;
- ne jamais attendre un délai fixe : `verifier*` réévalue jusqu'à 8 s,
  `attendreCalme()` attend la fin des requêtes ;
- vérifier l'état métier en base (`sql`, `demande`) **et** l'écran ;
- dans tout scénario de remplacement, finir par `verifierDavidNeVoitRien`
  (écran de David, lecture API sous son compte, notifications).

Ajouter un test SQL : un fichier `qa/metier/sql/NN_nom.sql` qui utilise
`verifier(scenario, libellé, condition)` (défini dans `10_imprevu.sql`).

Numéros de téléphone (D-024) : chaque acteur garde tout ce que l'API lui a
renvoyé (`acteur.reponsesApi` : corps des réponses et messages temps réel).
`numerosNonAutorises(acteur, { kevin: true, eliot: /rpc\/telephone_titulaire_accessible/ })`
(`e2e/lib/numeros.mjs`) liste les numéros connus reçus hors de ce qui est
autorisé, quel que soit leur format. Scénario `24_confidentialite_telephones`,
tests SQL `96_confidentialite_telephones.sql` (matrice rôles × états, listes
blanches des colonnes et fonctions qui exposent un numéro, push).

Chat après le Swend (D-023b) : tests SQL `99b_chat_apres_swend.sql` (heures
d'ouverture et changements d'heure, rattrapage, retard, participants, accès,
non-lus, messages, push, fermeture D-023c), concurrence (3 moteurs
simultanés), scénario E2E `25_chat_apres_swend`. Dans les scénarios, la
fixture vide `chat_apres_swend_service` : poser la mise en service avant
d'appeler `ouvrir_chats_apres_swend(<instant>)`.

Lectures API « en tant que » sur `pactes` : toujours avec des colonnes
explicites (`lireComme('kevin', 'pactes', 'select=id')`) — comme en
production, `select=*` y est refusé (privilèges colonne par colonne).

## Lire un échec

Le rapport indique le scénario, l'étape, l'attendu et l'obtenu :

```
FAIL — Kevin : "Tu prends la place d'Eliot"
       scénario : desistement
       étape    : Kevin ne voit plus ce Swend
       attendu  : « Tu prends la place d'Eliot » absent de l'écran de kevin
       obtenu   : présent : …Tu prends la place d'Eliot…
       artefacts : qa/artifacts/2026-09-27-10-12-00-full/desistement
```

Dans le dossier d'artefacts :

- `echec.txt` : scénario, étape, attendu / obtenu (et la pile d'appel si erreur technique) ;
- `<acteur>.png` : capture d'écran de chaque utilisateur au moment de l'échec ;
- `<acteur>.log` : texte accessible de l'écran, liens Messages/WhatsApp ouverts, console ;
- `etat_metier.json` : Swends, personnes de confiance, événements, messages, notifications.

`qa/artifacts/dernier` pointe vers la dernière exécution E2E ;
`qa/artifacts/<date>-metier/` contient les journaux des tests métier en échec.
Journaux de la pile : `qa/stack.sh logs`.

## Protection de la production

Le banc refuse de démarrer si quoi que ce soit ressemble à la production :

1. `qa/lib/garde_fou.sh` (appelé par chaque commande, et par le lanceur E2E) :
   - l'API visée doit être `127.0.0.1` / `localhost` ;
   - aucune variable `QA_*`, `SUPABASE*`, `DATABASE_URL`, `PG*` ne doit contenir
     le project ref de production (lu dans `lib/constants.dart`), `.supabase.co`,
     `supabase.com` ou `pooler.supabase` ;
   - aucune variable `*SERVICE_ROLE*` ne doit être définie ;
   - `PGHOST` doit être local ;
   - autotest à chaque `run_metier.sh` (8 cas, dont un ref de production simulé).
2. L'app QA est construite depuis une **copie** (`qa/.work/app`) dont
   `constants.dart` est réécrit vers la pile locale ; la build est ensuite
   fouillée : elle ne doit contenir ni le ref de production, ni
   `.supabase.co`, ni la clé anon de production, sinon elle est rejetée.
3. Chaque navigateur de test bloque toute requête hors de `127.0.0.1`
   (ports de l'API et de l'app) : rien ne peut sortir, même par erreur.
4. La pile n'écoute que sur `127.0.0.1` ; son secret JWT est propre au banc.
5. Rien du banc n'entre dans la build de production : pas de compte de
   test, de sélecteur de rôle, de stub ni de contournement dans `lib/`.

## Limites connues

- La base locale est une **réplique reconstruite** du schéma de production
  (d'après les migrations et le schéma documenté), pas une copie : un écart
  avec la production reste possible sur ce qui n'est pas versionné.
  Privilèges : sur `pactes`, la lecture est accordée colonne par colonne
  comme en production (depuis D-024 ; les colonnes ajoutées ensuite ne sont
  pas lisibles) ; les écritures restent accordées au niveau de la table.
- Auth simulée : connexion par mot de passe des 4 comptes seulement
  (l'inscription et la connexion par passkey ne sont pas couvertes).
- Realtime simulé : les changements sont relus toutes les 300 ms sous le
  compte de l'abonné (même visibilité que la RLS, pas le même mécanisme).
- Notifications push : vérifiées dans `notifications_log`, pas envoyées ;
  Messages / WhatsApp : l'URL ouverte est vérifiée, pas l'app elle-même.
- Web uniquement (Chromium, 400×860) : pas d'iOS natif, pas de comparaison
  visuelle au pixel.
- Les scénarios partagent une base : ils s'exécutent l'un après l'autre.
