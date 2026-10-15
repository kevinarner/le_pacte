# D-027-02

Niveau : 2 — préparé le 15/10/2026. Empreinte : donnée par
`scripts/paquet_controler.sh D-027-02 --avant-go`. Go d'Eliot.
**Pas de validation à ce jour. À ne pas exécuter avant la publication d'une
app du lot 3 compatible** (voir « Ordre d'exécution »).

## Objectif

Mettre en production le côté serveur du **lot 2 de D-027** (« En cas
d'imprévu » : annulation et conversations), décrit dans `DECISIONS.md`
(D-027, points 13 à 17 et « Choix techniques (lot 2) ») et
`PRODUCT_RULES.md` §3.5 à §3.8 :

1. **Titulaire remplacé** : `annuler_swend()` refuse `remplacement_accepte`
   quand le côté de l'appelant a un remplaçant sélectionné ; l'autre
   titulaire, non remplacé, peut toujours annuler.
2. **Annulation unique** `appliquer_annulation()` (titulaire, double
   remplacement ; prête pour H-3 / H du lot 4) : demandes en attente des deux
   côtés closes, statut, date, motif (`pactes.annule_motif`), notifications
   D-027 (une par personne), chat d'annulation.
3. **Chat d'annulation** entre les deux titulaires seulement, ouvert dans la
   même transaction, sans push (`chats_apres_swend.nature = 'annulation'`),
   lu par `mes_chats_swend()` ; `mes_chats_apres_swend()` (app publiée) ne
   renvoie que les chats après le Swend. Un message écrit dans ce chat est
   notifié « Prénom t’a écrit / Swend annulé · Restaurant »
   (`envoyer_message_apres_swend()`, jamais « Après le Swend ») ; le titre
   passe au tutoiement pour les deux natures (« Prénom t’a écrit / Après le
   Swend · Restaurant » pour le chat après le Swend, au lieu de « Prénom
   vous a écrit »).
4. **Conversations d'imprévu conservées** après annulation pour les
   personnes réellement sollicitées : lecture et écriture jusqu'au
   scellement d'un nouveau Swend entre les deux mêmes personnes (fermeture
   paire par paire, `fils_imprevu_fermes`, événement `fil_ferme`). Deux
   précisions **validées par Eliot le 15/10/2026** (`DECISIONS.md`, D-027,
   P1 et P2) : P1, une conversation où des messages ont déjà été échangés
   reste accessible et écrivable même sans demande envoyée ; P2, un nouveau
   scellement entre les mêmes personnes empêche l'annulation de l'ancien
   Swend de rouvrir leur conversation (scellement survenu avant
   l'annulation, après celui du Swend annulé : conversation fermée dès
   l'annulation).
5. **Numéro du titulaire (D-024) inchangé** : `telephone_titulaire_accessible()`
   suit exactement l'ancienne règle d'accès (`fiche_acces_d023a()`, même
   empreinte que l'ancienne `fiche_de_confiance_accessible()`).
6. `retirer_remplacant()` refuse `swend_inactif` sur un Swend annulé.

Aucune donnée existante n'est modifiée : deux colonnes ajoutées (motif
NULL ; nature `apres_swend` par défaut pour les chats existants, 0 en
production le 15/10), une table interne vide.

## Fichiers concernés

Artefacts : `sauvegarde.sql` (sauvegarde ciblée, une transaction),
`appliquer.sql` (préconditions, migration
`supabase/migrations/20261015000000_annulation_et_conversations.sql` en
copie exacte, assertions ; une transaction), `verifier.sql` (lecture seule),
`rollback.sql`.

Objets de production :
- créés : colonnes `public.pactes.annule_motif` (`text`, contrainte
  `pactes_annule_motif_valeurs`, protégée contre l'app par
  `proteger_annulation_pacte()`) et `public.chats_apres_swend.nature`
  (`text not null default 'apres_swend'`, contrainte
  `chats_apres_swend_nature_valeurs`) ; table interne
  `public.fils_imprevu_fermes` (RLS activée, aucun droit pour `public`,
  `anon`, `authenticated`) ; fonctions `mes_chats_swend()` (SECURITY
  INVOKER comme `mes_chats_apres_swend()`, `authenticated` seulement),
  `appliquer_annulation(uuid, text, text, uuid)`,
  `ouvrir_chat_annulation(uuid)`, `fiche_acces_d023a(uuid)`,
  `fil_conserve_apres_annulation(uuid)`, `cle_paire_fil_imprevu(uuid, uuid)`
  (internes, non exécutables par l'app) ;
- remplacées (même signature, mêmes droits) : `annuler_swend(uuid)`,
  `annuler_si_double_absence()`, `proteger_annulation_pacte()`,
  `fermer_chats_apres_nouveau_swend()`, `mes_chats_apres_swend()`,
  `fiche_de_confiance_accessible(uuid)`, `fil_ecriture_ouverte(uuid)`,
  `telephone_titulaire_accessible(uuid)`, `retirer_remplacant(uuid)`,
  `envoyer_message_apres_swend(uuid, text)` (textes de la push seulement) ;
- contraintes redéfinies : `pactes_annulation_complete` (une date sans
  auteur est admise pour les annulations système ; un motif `titulaire`
  exige un auteur), `evenements_fil_code_check` (+ `fil_ferme`) ;
- schéma interne `sauvegarde` : tables `d027_02_fonctions_20261015`,
  `d027_02_pactes_20261015`, `d027_02_chats_20261015`.

Aucune politique RLS réécrite (les politiques existantes appellent
`fiche_de_confiance_accessible()` et `fil_ecriture_ouverte()`, dont la règle
change), aucun déclencheur créé ou supprimé, aucune Edge Function, aucune
planification, aucun objet `auth`.

Niveau 2 : la migration change des règles d'accès appliquées par la RLS
(lecture et écriture des conversations après annulation), le comportement
d'actions réelles (annulation, double remplacement, retrait) et les
notifications ; le rollback supprime des colonnes (DDL destructif, limité
aux objets créés par ce paquet, contenu copié avant). Sauvegarde ciblée,
rollback, tests et préconditions obligatoires.

## Préconditions

**Ordre.** À exécuter **après** D-027-01 (`appliquer.sql` refuse sinon) et
**après** la publication d'une app du lot 3 compatible (non vérifiable par
SQL : voir « Ordre d'exécution »).

**État relu en lecture seule le 15/10/2026** (endpoint `…/read-only`) :
D-027-01 appliqué, D-027-02 non appliqué ; 0 Swend scellé puis annulé,
0 Swend annulé avec conversation, 0 chat, 0 annulation datée sans auteur ;
contraintes `pactes_annulation_complete` et `evenements_fil_code_check`
identiques à la base de test. Les 10 fonctions remplacées : 8 identiques aux
migrations du dépôt ; **2 dans une version de production antérieure** :
`annuler_swend` (`95d5c90f…` : sans la modification du commit `5358f5d`,
texte au remplaçant) et `annuler_si_double_absence` (`c39f19eb…` : sans
l'élision du commit `7be0d90`). Le paquet est construit sur ces versions de
production (préconditions et rollback) ; la répétition les reproduit.

Déclencheurs (relus le 15/10, non modifiés par ce paquet) : le double
remplacement passe en production par `on_remplacant_selectionne`, `AFTER
INSERT OR UPDATE OF selectionne ON public.remplacants FOR EACH ROW EXECUTE
FUNCTION annuler_si_double_absence()`, actif — même définition que
`trg_annuler_si_double_absence` du banc QA, seul le nom diffère (écart
historique admis, `qa/db/parite/declencheurs_admis.tsv`). Il n'est **pas
absent** (une première requête filtrait sur le nom QA). `sauvegarde.sql` et
`appliquer.sql` exigent un seul déclencheur sur `remplacants` appelant
`annuler_si_double_absence()`, actif et de cette définition (nom ignoré),
plus 2 déclencheurs actifs de fermeture au scellement et 1 de protection de
l'annulation sur `pactes` ; ils sont copiés dans la sauvegarde, et
`appliquer.sql` puis `rollback.sql` vérifient qu'ils sont inchangés (noms,
état, définitions). À relire juste avant le Go :

```sql
select (select json_object_agg(p.proname, md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')))
          from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('annuler_si_double_absence', 'annuler_swend',
             'envoyer_message_apres_swend',
             'fermer_chats_apres_nouveau_swend', 'fiche_de_confiance_accessible',
             'fil_ecriture_ouverte', 'mes_chats_apres_swend', 'proteger_annulation_pacte',
             'retirer_remplacant', 'telephone_titulaire_accessible')) as md5_fonctions,
       to_regclass('public.imprevus_declares') is not null as d027_01,
       to_regclass('public.fils_imprevu_fermes') is null as pas_encore_applique,
       (select count(*) from public.pactes p
         where p.statut in ('annule', 'annuleDoubleAbsence') and p.scelle_le is not null
           and exists (select 1 from public.remplacants r where r.pacte_id = p.id
                       and (exists (select 1 from public.evenements_fil e
                                    where e.remplacant_id = r.id and e.code = 'demande_envoyee')
                            or exists (select 1 from public.messages m where m.remplacant_id = r.id))))
         as annules_avec_conversation,                                    -- 0
       (select count(*) from public.chats_apres_swend) as chats;
```

Empreintes attendues (corps normalisé) : `annuler_si_double_absence`
`c39f19eb…`, `annuler_swend` `95d5c90f…`, `envoyer_message_apres_swend`
`32be7513…`, `fermer_chats_apres_nouveau_swend`
`c5159594…`, `fiche_de_confiance_accessible` `6d610f3a…`,
`fil_ecriture_ouverte` `b62fe262…`, `mes_chats_apres_swend` `ef7f9efe…`,
`proteger_annulation_pacte` `c8381429…`, `retirer_remplacant` `3c85b326…`,
`telephone_titulaire_accessible` `4cff9f4b…` (valeurs complètes dans
`appliquer.sql`).

`sauvegarde.sql` et `appliquer.sql` revérifient tout avant d'écrire et
annulent tout sinon : D-027-01 appliqué, D-027-02 pas encore appliqué,
10 empreintes identiques, contraintes d'origine, déclencheurs ci-dessus, **aucun Swend scellé puis
annulé avec une conversation** (sinon la règle des conversations conservées
rendrait un accès retiré : arbitrage produit nécessaire, paquet à refaire),
sauvegarde faite (pour appliquer).

**Tests** (banc QA, 15/10/2026) : voir `DECISIONS.md` (D-027, « Mise en
production ») — suite `qa/metier/sql/99g_annulation_conversations.sql`
(79 vérifications), suites réalignées (`80`, `90`, `97`, `98`, `99`, `99b`,
`99f`), 3 nouvelles courses de concurrence, régression complète métier et
E2E.

**Répétition** sur une base locale reproduisant la production attendue
(toutes les migrations sauf celle-ci, `annuler_swend` et
`annuler_si_double_absence` remplacées par leurs définitions de production
relues le 15/10, déclencheurs de `remplacants` renommés comme en production
— `on_remplacant_selectionne`, `on_remplacant_change` —, comptes et données
fictifs : un Swend scellé avec une demande en cours, un Swend annulé jamais
scellé, un Swend scellé puis annulé sans conversation ; journal et scripts
conservés dans `qa/preuves/2026-10-15_D-027-02_repetition*`) :
- déclencheur du double remplacement désactivé : `sauvegarde.sql` et
  `appliquer.sql` refusés ; déclencheur en double : `sauvegarde.sql` refusé ;
- `appliquer.sql` sans sauvegarde refusé (« sauvegarde absente ») ;
  `sauvegarde.sql` OK ; `appliquer.sql` OK ; `verifier.sql` OK (0 chat,
  0 conversation fermée, 0 motif, 3 Swends = 3 sauvegardés) ;
- seconde exécution d'`appliquer.sql` et de `sauvegarde.sql` refusée
  (« déjà appliqué ») ;
- `rollback.sql` immédiat OK : 10/10 fonctions à l'empreinte et aux droits de
  la sauvegarde, 2/2 contraintes identiques, colonnes retirées ;
  `verifier.sql` refuse ensuite ; second rollback refusé ; réapplication OK ;
- usage réel simulé (annulation par Eliot avec Kevin sollicité, double
  remplacement, scellement Eliot–Kevin) : 2 chats d'annulation, 1
  conversation fermée, 1 événement `fil_ferme`, 1 annulation datée sans
  auteur ; `rollback.sql` après usage OK : chats d'annulation et `nature`
  conservés, `mes_chats_apres_swend()` filtrée conservée (Eliot : 0 chat
  affiché), contrainte des événements gardée élargie, contrainte
  d'annulation sous la forme « auteur ⇒ date », motifs et fermetures copiés
  dans `sauvegarde` ; l'ancien `annuler_swend()` fonctionne ensuite ; le
  double remplacement passe par `on_remplacant_selectionne` après
  application (motif `double_remplacement`) et après rollback, déclencheur
  toujours unique et actif ;
- base avec un Swend scellé puis annulé ayant une conversation :
  `appliquer.sql` refusé (« arbitrage nécessaire ») ;
- toutes les suites SQL métier sur une base où le lot 2 vient du paquet (et
  non de la migration), déclencheurs aux noms de production : 1063/0
  (`qa/preuves/2026-10-15_D-027-02_suites_base_paquet.txt`).

## Impact attendu

- Immédiat : aucune donnée existante modifiée. Effets dès l'exécution :
  - un titulaire remplacé qui tente d'annuler est refusé
    (`remplacement_accepte`) ;
  - textes des push d'annulation et du double remplacement (D-027) ;
  - titre des push de message des chats entre participants : « Prénom t’a
    écrit » (au lieu de « Prénom vous a écrit ») ;
  - à chaque annulation : chat d'annulation entre titulaires (invisible
    dans une app qui ne lit pas `mes_chats_swend()`), conversations
    d'imprévu conservées pour les personnes sollicitées (dans l'app du
    lot 1, elles restent affichées en lecture seule) ;
  - un nouveau Swend scellé entre deux personnes ferme leurs conversations
    d'imprévu conservées (événement `fil_ferme`).
- Durée : une transaction courte (2 colonnes avec valeur par défaut
  constante, 1 table, 16 fonctions, 4 contraintes ; verrous brefs sur
  `pactes`, `chats_apres_swend`, `evenements_fil`).

## Vérifications après exécution

`verifier.sql` (lecture seule) ne lève aucune erreur et affiche :
`chats_annulation = 0`, `chats_apres_swend = chats_sauvegardes`,
`conversations_fermees = 0`, `annulations_avec_motif = 0`, `swends =
swends_sauvegardes` (hors Swends créés entre-temps).

Session de travail, en lecture seule ensuite : jobs pg_cron
(`swend-rappels`, `swend-gel-a-h`, `swend-chat-apres`) toujours `succeeded`.

## Rollback

Quand : régression constatée sur l'annulation, le double remplacement, les
conversations ou leurs accès. Exécuter
`scripts/prod_ecrire.sh D-027-02 <empreinte> --rollback`.

Effet : les 10 fonctions retrouvent leur définition de production d'origine
(contrôlée contre la sauvegarde : empreinte et droits) ; fonctions internes
et table `fils_imprevu_fermes` du lot 2 supprimées ; colonne `annule_motif`
supprimée (motifs copiés avant dans `sauvegarde.d027_02_rollback_annulations_<horodatage>`,
conversations fermées dans `sauvegarde.d027_02_rollback_fils_fermes_<horodatage>`).
Sans aucun chat d'annulation : `nature`, sa contrainte et `mes_chats_swend()`
supprimées, `mes_chats_apres_swend()` d'origine. **Avec au moins un chat
d'annulation** : ils sont conservés (aucun message supprimé), avec `nature`,
sa contrainte, `mes_chats_swend()` et `mes_chats_apres_swend()` filtrée —
sinon l'app les afficherait comme des chats après le Swend. Contrainte des
événements remise à l'identique s'il n'existe aucun événement `fil_ferme`,
sinon gardée élargie. Contrainte d'annulation remise à l'identique s'il
n'existe aucune annulation datée sans auteur, sinon sous la forme
« auteur ⇒ date » (compatible avec l'ancien code). Refusé si D-027-02 n'est
pas appliqué.

Ne rétablit pas : les conversations conservées redeviennent inaccessibles
aux personnes non sélectionnées (règle D-023a), les demandes closes par une
annulation restent closes, les chats d'annulation déjà ouverts restent
visibles des titulaires dans une app qui lit `mes_chats_swend()`.

App : l'app du lot 3 doit fonctionner sur une base sans D-027-02 (exigence
ci-dessous), donc aucun retour d'app n'est nécessaire pour un rollback de
la base.

## Sauvegardes

`sauvegarde.sql` (étape `sauvegarde`, avant toute modification), dans le
schéma interne `sauvegarde` (aucun accès pour l'app, vérifié) :
- `d027_02_fonctions_20261015` : définition exacte (`pg_get_functiondef`),
  droits et empreinte de chacune des 10 fonctions remplacées, et définitions
  des contraintes `pactes_annulation_complete` et `evenements_fil_code_check` ;
- `d027_02_pactes_20261015` : statut, scellement, auteur et date
  d'annulation de tous les Swends (identifiants et dates seulement) ;
- `d027_02_chats_20261015` : état des chats (identifiants, dates,
  fermeture, nombres de participants et de messages ; aucun contenu).

`appliquer.sql` prouve, contre cette copie, qu'aucun Swend ni chat existant
n'a changé.

## Ordre d'exécution (app du lot 3 d'abord, puis base)

Le lot 2 change ce que voient les utilisateurs (annulation refusée au
titulaire remplacé, Swend annulé de nouveau visible avec sa conversation
pour une personne sollicitée, événement `fil_ferme`) alors que l'app publiée
(lot 1) ne l'expose pas correctement : il n'est mis en production
qu'**après** une app du lot 3 compatible avec les deux bases.

**Exigences de compatibilité pour l'app du lot 3** (avec et sans D-027-02) :
1. Ne pas proposer `Annuler le Swend` à un titulaire dont le côté a un
   remplaçant sélectionné ; afficher un message explicite pour
   `remplacement_accepte`.
2. Décider de l'écriture d'une conversation d'imprévu par la base
   (`fil_ecriture_ouverte(id)`, déjà en production, `authenticated`), pas
   par la règle locale `conversationEnLectureSeule()` ; traiter un refus
   RLS à l'envoi (conversation fermée entre-temps).
3. Lire les chats par `mes_chats_swend()` et, si la fonction n'existe pas
   (base sans D-027-02 : erreur PostgREST « fonction introuvable »), se
   replier sur `mes_chats_apres_swend()` ; présenter `nature = 'annulation'`
   comme le chat d'annulation (jamais « Alors, ce Swend ? »).
4. Libellé de l'événement `fil_ferme` ; tolérer un code d'événement inconnu.
5. `pactes.annule_motif` facultatif (absent sans D-027-02).
6. Personne de confiance non sélectionnée sur un Swend annulé : présenter
   sa conversation conservée sans rien révéler d'autre (ni autres personnes,
   ni numéro).

**Vérifications pour décider de l'ordre** :
- V1 — E2E complet avec l'app du lot 3 sur une base **sans** D-027-02
  (production attendue) : vert, sinon l'app ne peut pas partir d'abord.
- V2 — E2E complet avec l'app du lot 3 sur une base **avec** D-027-02 : vert.
- V3 — l'app publiée (lot 1) sur une base avec D-027-02 (fenêtre si la base
  partait d'abord) : fait le 15/10, voir `DECISIONS.md` (D-027, « Mise en
  production ») — elle confirme que la base ne doit pas précéder l'app.
- V4 — juste avant le Go, en lecture seule : préconditions ci-dessus, et
  `.last_build_id` de `gh-pages` = celui de la build du lot 3.

**Anciennes apps encore ouvertes.** Publier l'app du lot 3 ne prouve pas
que tous les appareils l'utilisent. Le service worker de Flutter est
désactivé (`web/flutter_bootstrap.js`) : aucun cache hors ligne de l'app ;
une app du lot 1 ne survit que dans une session jamais rechargée (onglet
ouvert, app installée en mode `standalone` restée en arrière-plan), plus un
éventuel cache HTTP court de GitHub Pages (non vérifié depuis
l'environnement). L'app du lot 1 n'a aucun contrôle de version : rien ne
peut la forcer à se recharger. Ce qu'elle fait face à la base du lot 2
(mesuré, V3) reste sans effet sur les données ni sur la confidentialité :
annulation refusée avec un message générique (rien ne change), Swend annulé
réaffiché en lecture seule à une personne sollicitée, message accepté dans
une conversation conservée (conforme à la nouvelle règle) mais affichée
comme terminée de l'autre côté, chat d'annulation invisible, événement
`fil_ferme` sans libellé ; aucun numéro ni aucune autre fiche révélés.
Le risque résiduel est donc une confusion d'affichage, limitée aux Swends
qui vivent un imprévu ou une annulation pendant cette fenêtre.

**Ce que ce lot ne fait pas (décidé avec le Go du lot 3)** : ni mesure
d'adoption, ni rechargement automatique, ni contrôle de version. Aucun
délai d'attente n'est donc une garantie : une session jamais rechargée
reste du lot 1 quel que soit le délai, et **rien, côté serveur ou app, ne
permet de prouver qu'aucun appareil n'utilise encore le lot 1** au moment
de l'exécution. La transition repose sur la coordination avec les
utilisateurs, peu nombreux et connus, et sur l'innocuité mesurée ci-dessus
(V3) pour un appareil oublié.

**Procédure retenue (utilisateurs connus)** :
1. app du lot 3 publiée (niveau 1, Go à part) après V1 et V2 ; relever
   l'identifiant de build publié (`.last_build_id` de `gh-pages`) ;
2. fixer une fenêtre courte et annoncée (par exemple un soir sans Swend
   scellé à venir dans les heures qui suivent) ; prévenir chaque
   utilisateur actif ;
3. dans la fenêtre, faire recharger l'app par chacun : onglet rechargé,
   app installée fermée (balayée) puis rouverte ; chacun confirme (par
   exemple en ouvrant « Un imprévu ? » ou un Swend : seul le lot 3 affiche
   « Tu ne peux plus être là ? ») ; noter qui n'a pas confirmé ;
4. juste avant le Go, en lecture seule (V4) : préconditions ci-dessus
   (10 empreintes, D-027-02 absent, aucun Swend scellé puis annulé avec
   conversation), build publiée inchangée, et état des Swends à venir
   (aucun Swend scellé à venir avec une demande, une sélection ou un
   message de préférence — sinon prévenir les personnes concernées) ;
5. Go d'Eliot puis exécution de ce paquet par la porte (sauvegarde,
   appliquer, verifier) ;
6. vérifications en lecture seule (jobs pg_cron) ; redemander un
   rechargement à toute personne non confirmée à l'étape 3.
