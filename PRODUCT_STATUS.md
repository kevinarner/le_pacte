# SWEND — PRODUCT_STATUS

> Vue synthétique au **28/09/2026**. Règles : `PRODUCT_RULES.md` · décisions : `DECISIONS.md` · implémentation : `SWEND_README.md`.
> Dernier QA : `qa/run_full.sh` = PASS (métier 472 / 0, E2E 456 / 0, 20 / 20 scénarios). La colonne “Test réel” reflète uniquement les vérifications humaines explicitement tracées dans les documents.

| Sujet | Statut produit | Implémentation | QA | Test réel | Note courte |
|---|---|---|---|---|---|
| Banc QA permanent | Validé (D-017) | Implémenté | QA OK | Non applicable | Local uniquement, lancé à la main ; full regression avant un lot important. |
| Discuter après acceptation | Validé (D-007) | Implémenté | QA OK | Test réel à faire | « Écrire à [Prénom] » + « Discuter » conservés après acceptation. |
| Indisponibilité spontanée | Validé (D-008) | Implémenté | QA OK | Test réel à faire | En production depuis le 27/09 (migration exécutée, app déployée). |
| Notifications des actions directes | Validé (D-015) | Implémenté | QA OK | Test réel à faire | Push vérifiés dans le journal local, pas via Firebase ; textes à affiner. |
| Personnes de confiance actives après scellage | Validé (D-019) | Implémenté | QA OK | Test réel OK | Garanti par la base ; en production depuis le 27/09 (migration exécutée). |
| Maximum 2 contre-propositions de date | Validé (D-011) | Implémenté | QA OK | Test réel à faire | 2 au total (précisé le 27/09) ; garanti aussi par la base. |
| Double remplacement | Validé (D-005, D-021) | Implémenté | QA OK | Test réel à faire | Annulation automatique + push immédiate (D-021, en production depuis le 28/09) ; libellé affiché ≠ libellé de `PRODUCT_RULES.md` §8.5. |
| Annulation manuelle d’un Swend scellé | Validé (D-022) | Implémenté | QA OK | Test réel à faire | Titulaires seulement, jusqu’à l’heure du RDV ; historique « Passés et annulés » ; suppression d’un Swend scellé bloquée ; en attente de la migration `20260928000000`. |
| OTP téléphone | Validé pour plus tard (D-014) | Non implémenté | Non applicable | Non applicable | En attendant : numéro déclaratif et figé (implémenté). |
| Copier le message | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Canaux V1 : Messages, WhatsApp. |
| Rappels automatiques | Validé (D-021) | Implémenté | QA OK | Test réel à faire | J-7 / J-3 / J-1 à 18h, Jour J à H-3 (Paris) ; clic web et mobile vers la bonne destination ; en production depuis le 28/09 (migration, Edge Function, app, planification pg_cron active) ; test réel = réception d'une notification programmée sur un appareil. |
| Réservation V1 (manuelle) | Validé (D-020) | Implémenté (outil interne) | QA OK | Non applicable | Gérée manuellement par l'équipe Swend après scellage ; suivi interne dans Supabase (`reservations_suivi`, vue `reservations_a_suivre`) ; aucun état visible dans l'app. |
| Réservation automatisée (partenaires / API) | Validé pour plus tard (D-016, D-020) | Non implémenté | Non applicable | Non applicable | Fonctionnement cible à définir. |
| Historique / Refaire un Swend | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | — |
| Harmonisation tu/vous | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Aujourd'hui : vous côté titulaire, tu côté personne de confiance. |
| Staging | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Seul environnement de test : le banc QA local. |
| CI | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Le banc QA existe mais n'est pas branché sur une CI. |
| TestFlight / tests iOS natifs | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Seul le web est déployé ; QA en Chromium. |
