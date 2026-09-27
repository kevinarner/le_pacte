# SWEND — PRODUCT_STATUS

> Vue synthétique au **27/09/2026**. Règles : `PRODUCT_RULES.md` · décisions : `DECISIONS.md` · implémentation : `SWEND_README.md`.
> Dernier QA : `qa/run_full.sh` = PASS (métier 325 / 0, E2E 417 / 0, 18 / 18 scénarios). « Test réel » = essai manuel sur l'app en ligne ; aucun n'est tracé dans ces documents.

| Sujet | Statut produit | Implémentation | QA | Test réel | Note courte |
|---|---|---|---|---|---|
| Banc QA permanent | Validé (D-017) | Implémenté | QA OK | Non applicable | Local uniquement, lancé à la main ; full regression avant un lot important. |
| Discuter après acceptation | Validé (D-007) | Implémenté | QA OK | Test réel à faire | « Écrire à [Prénom] » + « Discuter » conservés après acceptation. |
| Indisponibilité spontanée | Validé (D-008) | Implémenté | QA OK | Test réel à faire | En production depuis le 27/09 (migration exécutée, app déployée). |
| Notifications des actions directes | Validé (D-015) | Implémenté | QA OK | Test réel à faire | Push vérifiés dans le journal local, pas via Firebase ; textes à affiner. |
| Maximum 2 contre-propositions de date | Validé (D-011) | Implémenté | QA manquant | Test réel à faire | Aucun scénario QA ne couvre la contre-proposition. |
| Double remplacement | Validé (D-005) | Implémenté | QA OK | Test réel à faire | Annulation automatique ; libellé affiché ≠ libellé de `PRODUCT_RULES.md` §8.5. |
| OTP téléphone | Validé pour plus tard (D-014) | Non implémenté | Non applicable | Non applicable | En attendant : numéro déclaratif et figé (implémenté). |
| Copier le message | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Canaux V1 : Messages, WhatsApp. |
| Rappels automatiques | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | J-7 / J-3 / J-1 / Jour J ; fréquence et contenu à définir. |
| Réservation | À décider (D-016) | Non implémenté | Non applicable | Non applicable | Un seul restaurant en dur ; modèle volontairement ouvert. |
| Historique / Refaire un Swend | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | — |
| Harmonisation tu/vous | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Aujourd'hui : vous côté titulaire, tu côté personne de confiance. |
| Staging | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Seul environnement de test : le banc QA local. |
| CI | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Le banc QA existe mais n'est pas branché sur une CI. |
| TestFlight / tests iOS natifs | Validé pour plus tard | Non implémenté | Non applicable | Non applicable | Seul le web est déployé ; QA en Chromium. |
