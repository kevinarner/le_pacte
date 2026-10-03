# Change packets de production

Un **change packet** est la seule forme sous laquelle un changement de
production Swend (SQL ou déploiement d'Edge Function) peut être exécuté
normalement. Il est versionné ici, immuable une fois validé, et exécuté
uniquement par la porte `scripts/prod_ecrire.sh`. Règles générales :
`CLAUDE.md` (racine).

> Tant que l'environnement « Swend – écriture prod » n'existe pas, aucune
> session Claude n'a de droit d'écriture : la porte s'arrête avant tout envoi
> et Kevin exécute les changements (`SWEND_README.md` §12).

## Contenu d'un paquet

Un dossier `supabase/changements/<ID>/`, `<ID>` de la forme `R1b-01`
(lettres, chiffres, tirets, puis `-` et deux chiffres) :

| Fichier | Rôle |
|---|---|
| `paquet.md` | Description lisible. Commence par `# <ID>` ; sections obligatoires : `## Objectif`, `## Fichiers concernés`, `## Préconditions`, `## Impact attendu`, `## Vérifications après exécution`, `## Rollback`, `## Sauvegardes` |
| `manifeste.json` | Ce que la porte exécute (voir ci-dessous) |
| artefacts (`*.sql`) | Le SQL exact, un fichier par étape. Aucun chemin : fichiers à plat dans le dossier |
| `validation.json` | Le « Go », écrit **après** la validation humaine (jamais à la création) |
| `journal/` | Reçus d'exécution écrits par la porte |

Aucun autre fichier n'est admis dans le dossier.

`manifeste.json` :

```json
{
  "id": "R1b-01",
  "niveau": 1,
  "projet": "ssciqjpaibdorvnkkhsk",
  "objectif": "Une phrase.",
  "sauvegardes": [],
  "etapes": [
    {"nom": "appliquer", "type": "sql_ecriture", "fichier": "appliquer.sql", "sha256": "<64 hex>"},
    {"nom": "verifier",  "type": "sql_lecture",  "fichier": "verifier.sql",  "sha256": "<64 hex>"}
  ],
  "rollback": [
    {"nom": "rollback",  "type": "sql_ecriture", "fichier": "rollback.sql",  "sha256": "<64 hex>"}
  ]
}
```

- `niveau` : 1 ou 2 (le niveau 3 n'est jamais un paquet, voir `CLAUDE.md`).
  Niveaux 1 et 2 : Go d’Eliot obligatoire et suffisant. Kevin peut être
  consulté, sans approbation bloquante. Niveau 2 : sauvegarde adaptée
  (`sauvegardes` non vide ou `sauvegarde_justification` motivée), rollback,
  tests et préconditions restent obligatoires. Le niveau 3 reste humain uniquement.
- Étapes :
  - `sql_ecriture` : endpoint d'écriture. Le SQL **doit commencer par
    `begin;` et finir par `commit;`**, sauf `"transaction": false` justifié
    dans `paquet.md`.
  - `sql_lecture` : endpoint `…/read-only`.
  - `edge_function` : déploiement d'une Edge Function, par la même porte.
    Exemple :
    `{"nom": "deployer", "type": "edge_function", "fonction": "send-notification", "fichier": "send-notification.ts", "sha256": "…", "verify_jwt": true}`.
    - **Fonctions concernées :** seulement une fonction existante du dépôt,
      d'un seul fichier `supabase/functions/<fonction>/index.ts`.
    - **Application :** l'artefact doit être **identique à la source
      versionnée** de la fonction, ce qui est déployé est donc ce qui est
      relu. La porte refuse si la source change après le Go.
    - **Rollback :** l'artefact est la version précédente, conservée dans le
      paquet.
    - **Déploiement :** la porte l'envoie tel quel en `index.ts` (`POST
      …/functions/deploy?slug=<fonction>`, `entrypoint_path` `index.ts`,
      `verify_jwt` du manifeste), sans bundler ni dépendance locale :
      Supabase résout les imports à la construction.
    - **Contrôle après déploiement :** `GET …/functions/<fonction>` doit
      confirmer le slug, le statut `ACTIVE` et `verify_jwt`. La version et
      `ezbr_sha256` vont au reçu.
- Ordre d'application : `sauvegardes`, puis `etapes`. `--rollback` exécute
  `rollback` seulement. Sans rollback exécutable : `rollback_justification`.

Le dossier `_modele/` contient un paquet vide à copier.

## Cycle de vie

1. **Préparation** (session de travail, lecture seule) : écrire le paquet,
   calculer les SHA-256 (`sha256sum`), répéter le SQL en local (banc QA ou
   données fictives), vérifier les préconditions et documenter les résultats
   des tests, la sauvegarde adaptée et le rollback, puis committer. Le Go
   d’Eliot ne dispense jamais de ces contrôles. Puis
   `scripts/paquet_controler.sh <ID> --avant-go` affiche l'**empreinte** du
   paquet : sha256 de tous ses fichiers. Présenter le paquet et ses 12
   premiers caractères.
2. **Go** : Eliot écrit `Go <ID>` dans la conversation. Puis
   `scripts/paquet_controler.sh <ID> --enregistrer-go "Go <ID>" --par Eliot` écrit `validation.json` avec cette
   empreinte, à committer. Un paquet validé ne se modifie plus : toute
   correction = nouvel identifiant (`R1b-02`).
   **`--par` est déclaratif** : il trace qui a donné le Go, il **n'authentifie
   personne**. Ajouter `--par Kevin` seulement si Kevin a réellement approuvé.
   Les reçus reprennent uniquement les approbateurs enregistrés, sans ajout
   automatique. Claude ne peut pas vérifier qui a écrit dans la conversation,
   et rien n'empêche techniquement d'écrire `validation.json` à la main. Le
   contrôle humain effectif est le **clic d'approbation** que Claude Code
   demande avant d'exécuter la porte (règle `ask`).
3. **Exécution** (session « Swend – écriture prod » seulement) :
   `scripts/prod_ecrire.sh <ID> <empreinte-12>`. Claude Code demande alors
   l'approbation humaine (règle `ask`) : vérifier que l'identifiant et
   l'empreinte affichés sont ceux du Go. La porte refuse, **avant tout
   envoi**, si :
   - le paquet, un artefact, `scripts/`, `.claude/` ou `CLAUDE.md` a changé
     ou n'est pas commité ;
   - un SHA-256 ne correspond pas, ou l'empreinte diffère de celle du Go ;
   - il n'y a pas de `validation.json` versionné pour cette empreinte ;
   - la session n'a pas `SWEND_SESSION_ECRITURE=1` ;
   - le paquet a déjà été appliqué avec succès.

   Puis elle exécute les étapes dans l'ordre et s'arrête à la première erreur
   HTTP. Le reçu `journal/<horodatage>-<mode>.log` contient le plan, les
   empreintes, le commit, le code HTTP et la réponse de chaque étape, et
   `RESULTAT: SUCCES|ECHEC`. Aucun identifiant n'y figure : la porte n'en lit
   aucun, le proxy de l'environnement les ajoute hors de la session.
4. **Reçu** : la session d'écriture committe le seul fichier de journal et le
   rapporte. La session de travail vérifie la production en lecture seule et
   met la documentation à jour.

## Garde-fous et leurs limites

| Garde-fou | Ce qu'il garantit | Ce qu'il ne garantit pas |
|---|---|---|
| Endpoint `…/database/query/read-only` | Une requête envoyée là ne peut pas écrire, côté Supabase, quel que soit le jeton | Rien n'oblige à l'utiliser : avec un jeton d'écriture présent, l'endpoint d'écriture reste joignable |
| Porte `scripts/prod_ecrire.sh` | Exécute exactement ce qui a été validé (SHA-256, empreinte, commit, Go), journalise, s'arrête à l'erreur | Rien n'empêche une autre commande d'appeler l'API : c'est le rôle des deux lignes suivantes |
| Règle `ask` (`.claude/settings.json`) | Claude Code demande l'approbation humaine pour les formes `scripts/prod_ecrire.sh …`, `./scripts/…`, `bash scripts/…`, même en mode auto | Ne voit pas un appel lancé autrement ; une règle Bash n'est pas une frontière de sécurité (documentation Claude Code) |
| Hook `.claude/hooks/garde_prod.py` | Bloque les commandes Bash, ainsi que les scripts locaux qu'elles exécutent directement, qui visent la production avec un outil réseau autrement qu'en lecture `…/read-only`. Couvre `curl`, `wget`, Python, Node, `sh -c`, `/usr/bin/curl`, les commandes composées, les méthodes DELETE / PATCH / PUT, `*.supabase.co`, le CLI `supabase`, `psql`. Bloque aussi la porte appelée sous une forme non canonique | Analyse du texte seulement : une URL fabriquée par morceaux, un module importé indirectement, un programme compilé ou un fichier non exécuté directement (Makefile…) passent. Faux positifs possibles : un message de commit qui cite une URL d'écriture avec `curl` est bloqué |
| Exemptions du hook | `bash -n` / `sh -n` (contrôle de syntaxe, rien n'est exécuté) ; le contenu des fichiers de garde-fou nommés dans `GARDE_FOUS` n'est pas analysé (il contient forcément les motifs recherchés) | Une modification de ces fichiers n'est pas vue par le hook : la porte refuse alors de s'exécuter tant qu'elle n'est pas commitée, mais rien n'empêche une autre commande de les exécuter |
| Environnement dédié (hors dépôt) | Le jeton d'écriture n'existe que dans les sessions « Swend – écriture prod » | Dans cet environnement, tout processus qui passe par le proxy peut utiliser le jeton : d'où une session stérile (ni dépendances, ni QA) |

Les tests de ces garde-fous, sans production, sont dans
`scripts/tests/test_garde_prod.sh` (paquets fictifs, faux serveur local,
cas du hook dans `scripts/tests/cas_hook.tsv`).

Le contrôleur valide les artefacts et la présence des sections obligatoires ;
la pertinence de la sauvegarde, les résultats des tests et la satisfaction
des préconditions doivent être vérifiés avant le Go et avant exécution.

Pour un environnement sans serveur localhost :
`scripts/tests/test_garde_prod.sh --validation-only` teste les validations
aux niveaux 1/2 et les obligations du niveau 2 sans réseau. La suite complète
reste nécessaire pour les envois HTTP fictifs, les reçus et les déploiements.
