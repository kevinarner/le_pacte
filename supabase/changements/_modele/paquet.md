# <ID>

Niveau : 1 | 2 — préparé le JJ/MM/AAAA. Empreinte : donnée par
`scripts/paquet_controler.sh <ID> --avant-go`.

## Objectif

## Fichiers concernés

Objets de production touchés, et artefacts du paquet (`appliquer.sql`,
`verifier.sql`, `rollback.sql`).

## Préconditions

État de production vérifié en lecture seule avant exécution (requête et
résultat attendu).

## Impact attendu

## Vérifications après exécution

`verifier.sql` et résultat attendu ; vérifications complémentaires de la
session de travail.

## Rollback

Quand l'utiliser, effet attendu, ce qu'il ne rétablit pas.

## Sauvegardes

Instantané pris avant exécution (obligatoire au niveau 2), ou pourquoi aucun.
