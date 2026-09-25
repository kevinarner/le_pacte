# Synthèse technique — Swend

> **À maintenir à jour.** Ce document décrit l'état réel du produit et du code à un instant donné. Toute session de développement qui touche au schéma de données, aux règles de sécurité, au workflow de déploiement ou à une décision d'architecture doit mettre ce fichier à jour dans le même commit — pas après coup. Dernière mise à jour : **25 septembre 2026**.

## 1. Le produit

**Swend** (renommée depuis "Pakt" le 23/09, elle-même renommée depuis "Le Pacte" le 03/09 — nom et nom de domaine `swend.fr` déjà actés côté produit) est une application où deux personnes fixent d'avance un déjeuner ou un dîner, sans savoir à l'avance qui — du titulaire ou d'un remplaçant — sera réellement présent le jour J. Chaque partie peut, à tout moment avant le jour J, déléguer sa présence à l'un de ses propres remplaçants, sans que l'autre partie ne le sache. Ce secret est la règle produit centrale et elle irrigue tout le modèle de données (section 4).

**V1 : si les deux parties délèguent leur présence, le pacte est annulé automatiquement.** Faire se rencontrer deux remplaçants qui ne se connaissent pas n'est pas géré pour l'instant (peut être gênant). Les deux sont prévenus (dans l'app et par notification push) et peuvent recréer un pacte s'ils le souhaitent — voir section 4 (`statut = annuleDoubleAbsence`) et section 7.4.

## 2. Stack technique

| Couche | Choix | État |
|---|---|---|
| Frontend | Flutter (web + iOS/Android scaffoldés) | Web déployé et utilisé ; iOS/Android jamais publiés |
| Backend | Supabase (Postgres + Auth + Data API/PostgREST + RLS) | En production |
| Notifications push | Firebase Cloud Messaging (FCM), utilisé seul — pas tout Firebase | **Complet et en production (29/08)** : projet Firebase, intégration client, Edge Function, déclencheurs Postgres sur tous les événements, routage au clic. |
| Analytics | PostHog | Prévu, pas encore implémenté |
| Hébergement web | GitHub Pages | En production, https://kevinarner.github.io/le_pacte/ |

Décision backend (voir historique de conversation) : Supabase a été choisi plutôt que Firestore/Firebase complet pour rester en SQL (équipe à l'aise avec SQL, besoin d'analyses facilement requêtables), viser 3+ ans sur les paliers gratuits pour ~5000 utilisateurs, et parce que FCM peut s'utiliser seul sans adopter tout l'écosystème Firebase.

### Dépendances Flutter clés (`pubspec.yaml`)
- `supabase_flutter` — client Supabase (Auth + Data API).
- `image_picker` — sélection de photo (profil), **stockage local uniquement pour l'instant, jamais envoyée à Supabase Storage**.
- `url_launcher` — ouverture du lien restaurant / SMS d'invitation.
- Aucune dépendance ajoutée pour le sélecteur de contacts (03/09) : `lib/services/contact_picker_service.dart` utilise `dart:js_interop`/`dart:js_interop_unsafe`, tous deux dans le SDK Dart — évite d'ajouter `package:web` en dépendance directe rien que pour ça, et évite le piège `flutter clean` (section 3) qui ne concerne que l'ajout d'un vrai plugin.

## 3. Organisation Git & workflow de déploiement

- **Branche de développement** : `claude/github-files-list-vxwef9` — tout le code source y est commité.
- **`main`** : fast-forwardée pour matcher la branche de dev après chaque session (ne contient jamais de commit propre à elle).
- **`gh-pages`** : contient uniquement le **résultat compilé** (`flutter build web`), pas le code source. C'est elle que GitHub Pages sert.

Séquence de déploiement standard :
```bash
flutter build web --release --base-href /le_pacte/
# copier build/web/ sur la branche gh-pages (via un git worktree), commit, push
# puis fast-forward main sur la branche de dev
```
**Après l'ajout d'un nouveau plugin ayant une implémentation web** (`pubspec.yaml` modifié), faire `flutter clean` avant ce build — sinon le fichier généré qui enregistre les plugins web peut rester périmé et silencieusement ignorer le nouveau plugin (voir section 8, bug `shared_preferences` puis `firebase_core`, rencontré deux fois).

## 4. Modèle de données (Supabase / Postgres)

### `profiles`
Un compte = une ligne. `id` = `auth.uid()`. Colonnes : `prenom`, `nom`, `telephone`, `email`.
RLS : chacun ne voit/modifie que sa propre ligne. Créée automatiquement par le trigger `handle_new_user()` (section 5) au moment de l'inscription — jamais insérée depuis l'app.
**`telephone` est unique** (index unique partiel, `where telephone <> ''`, ajouté le 27/08 — voir section 8) : tout le rattachement automatique (destinataire, remplaçants) repose sur ce numéro comme identifiant fiable, ça ne peut fonctionner que si deux comptes ne peuvent jamais le partager.

### `restaurants`
Un seul restaurant en dur aujourd'hui (« Au père Lapin »), avec ses créneaux réels de déjeuner/dîner. Plusieurs restaurants proposés au choix est une évolution prévue mais pas commencée.
RLS : lecture publique pour `authenticated` (`using (true)`) — les infos du restaurant ne sont pas confidentielles. **Cette policy manquait initialement** (bug corrigé le 24/08 : la RLS était activée sans policy de lecture, ce qui bloquait tout accès avec une erreur 406 — voir section 8).

### `pactes`
La ligne partagée entre les deux parties. Deux catégories de colonnes bien distinctes :

**Colonnes accordées à `authenticated`** (lisibles/écrivables par l'app) : `id`, `type`, `statut`, `dates_proposees`, `date_retenue`, `nombre_echanges_date`, `restaurant_id`, `initiateur_id`, `initiateur_nom`, `destinataire_id`, `destinataire_nom`, `destinataire_telephone`, `created_at`.

**20 colonnes jamais accordées à `authenticated`** : `initiateur_remplacant_{1..5}_{nom,telephone}` et `destinataire_remplacant_{1..5}_{nom,telephone}`. Elles existent uniquement pour garder un historique permanent de « qui a remplacé qui », **lisible seulement via l'éditeur SQL Supabase ou le `service_role`**, jamais par l'app cliente — même après la fin du pacte. Remplies automatiquement par un trigger (section 5), jamais écrites par le code Flutter.

Ce cloisonnement colonne-par-colonne (`GRANT SELECT (col1, col2, ...) ON pactes TO authenticated`, tout le reste implicitement refusé) est le mécanisme qui rend ces 20 colonnes invisibles à l'app, en complément de la RLS classique (qui, elle, filtre les *lignes*, pas les colonnes).

`statut` (enum, valeurs exactes utilisées dans le code et en base) :
`enAttenteChoixDateDestinataire` → `enAttenteChoixDateInitiateur` (allers-retours de négociation de date, plafonnés à 2) → `enAttenteReponse` → `confirme` → `maintenu`, `annule`, ou `annuleDoubleAbsence` (les deux parties ont délégué leur présence — voir section 5 et 7.4).

Important : **aucun champ de statut de présence n'existe sur `pactes`**. Ni l'initiateur ni le destinataire ne peuvent lire, même indirectement, si l'autre partie a délégué sa présence — cette information vit exclusivement dans `remplacants`, cloisonnée par côté (voir ci-dessous). C'est une correction volontaire par rapport à une première version du schéma qui stockait un statut de présence par côté directement sur `pactes`.

### `remplacants`
Une ligne par remplaçant potentiel, propre à un pacte et à un côté (`cote` = `'initiateur'` ou `'destinataire'`) : `pacte_id`, `cote`, `prenom`, `nom`, `telephone` (obligatoire côté app depuis le 27/08 — nécessaire pour relier un compte), `email`, `selectionne` (booléen — celui-ci a été délégué), `profil_id` (nullable — rempli une fois que ce remplaçant a créé un compte, voir section 5 et 7.5).
RLS SELECT : **le titulaire du côté concerné**, OU **le remplaçant lui-même** une fois `profil_id` lié à son compte (ajouté le 27/08 — la policy initiale ne couvrait que le titulaire, pas le remplaçant, qui ne pouvait donc pas savoir sur quels pactes il avait été ajouté).
Plafond applicatif : 5 remplaçants maximum par côté (`RemplacantsForm.maximum` dans `lib/widgets/remplacants_form.dart`), pour que les 20 colonnes cachées de `pactes` puissent avoir un nombre fixe de colonnes.
**`demande_statut`** (24/09, texte nullable, `null`/`'envoyee'`/`'refusee'`/`'cloturee'`/`'acceptee'`) — cycle de vie d'une demande envoyée dans le cadre du parcours "Un imprévu ?" (voir 7.6). `selectionne` garde exactement son sens d'origine ("cette personne se présentera le jour J") : il ne passe à `true` que lorsque la personne sollicitée **accepte**, jamais directement au clic du titulaire — `annuler_si_double_absence()` continue de tourner sans aucune modification.

### `messages`
Un fil de discussion privé par remplaçant (`remplacant_id`, `expediteur_id`, `contenu`, `created_at`) — pas de `pacte_id`/`cote` dupliqués, ils se retrouvent via `remplacant_id`. Voir section 7.5.
RLS : lisible/écrivable par le titulaire du côté concerné OU par le remplaçant lié (`remplacants.profil_id = auth.uid()`). Realtime activé (`alter publication supabase_realtime add table messages`) pour la réception en direct.

### `device_tokens`
Un token FCM par appareil/navigateur (`profile_id`, `token`, `plateforme`, `created_at`). Contrainte d'unicité sur `token` (le client fait un `upsert(onConflict: 'token')` à chaque connexion), FK `profile_id → profiles(id) on delete cascade`. RLS : chacun ne gère que ses propres tokens (`profile_id = auth.uid()`) ; la future fonction serveur d'envoi lira toutes les lignes via la clé `service_role`, qui contourne RLS.

### `suggestions_restaurant` et `messages_contact` (03/09)
Écriture seule côté app, pour le sous-menu "Nous contacter" du hub (`lib/services/contact_repository.dart`). `suggestions_restaurant` : `profile_id`, `nom`, `lien` (nullable), `created_at`. `messages_contact` : `profile_id`, `objet`, `message`, `created_at`. RLS : `insert` uniquement, réservé à `profile_id = auth.uid()` — aucune policy `select`, les soumissions sont consultées directement dans le Dashboard Supabase, pas depuis l'app. Le formulaire "Autres" stocke pour l'instant sans envoyer de vrai email : aucune boîte de contact n'existe encore côté infra.

## 5. Fonctions & déclencheurs `SECURITY DEFINER`

Ces fonctions tournent avec les droits du propriétaire de la base, pas ceux de l'utilisateur connecté — elles contournent volontairement RLS/grants pour des opérations précises que l'app ne doit jamais faire elle-même.

- **`handle_new_user()`** — trigger `after insert` sur `auth.users`. Crée la ligne `profiles` correspondante, rattache automatiquement tout pacte en attente dont `destinataire_telephone` correspond au numéro du nouvel inscrit (met à jour `destinataire_id`), ET (depuis le 27/08) relie de la même façon tous les `remplacants.profil_id` correspondants — potentiellement plusieurs à la fois, un même numéro pouvant apparaître sur plusieurs pactes.
- **`synchroniser_remplacants_caches()`** — trigger `after insert/update/delete` sur `remplacants`. Recopie chaque remplaçant dans l'emplacement fixe correspondant parmi les 20 colonnes cachées de `pactes`, via `row_number() over (partition by cote order by id)`. C'est le seul mécanisme qui écrit dans ces 20 colonnes.
- **`trouver_profil_par_telephone(p_telephone text) returns uuid`** — RPC restreinte, appelée par l'app à la création d'un pacte (pour savoir si le destinataire a déjà un compte) et à l'ajout d'un remplaçant (pour lier `profil_id` immédiatement s'il a déjà un compte, sans attendre une inscription future). Ne renvoie qu'un UUID (ou rien), jamais les autres champs du profil — nécessaire car la RLS de `profiles` interdit sinon toute lecture du profil d'un tiers.
- **`annuler_si_double_absence()`** — trigger `after insert or update of selectionne` sur `remplacants`. Quand un côté sélectionne un remplaçant, vérifie si l'autre côté en a déjà un sélectionné pour ce même pacte ; si oui, bascule `pactes.statut` sur `annuleDoubleAbsence`. Doit obligatoirement tourner en `SECURITY DEFINER` : c'est le seul endroit du système qui a le droit de comparer les deux côtés d'un même pacte, l'app cliente n'ayant jamais accès aux remplaçants de l'autre partie (RLS par côté, section 4). Depuis le 29/08, notifie aussi les deux parties (voir plus bas).
- **`notifier(p_profile_id, p_title, p_body, p_data)`** — fonction commune (29/08) utilisée par tous les déclencheurs de notification ci-dessous. Appelle l'Edge Function `send-notification` via `pg_net` (requête HTTP asynchrone, ne bloque jamais la transaction), authentifiée avec la clé `service_role` lue dans le **Vault** de Supabase (secret `service_role_key_notifications` — jamais en clair dans le code). Toute erreur interne (secret manquant, etc.) est avalée et journalisée en warning : l'envoi d'une notification ne doit jamais faire échouer l'action réelle.
- **`notifier_nouveau_pacte()`** — trigger `after insert` sur `pactes`. Notifie le destinataire (si son compte existe déjà) : "{Prénom} te propose de faire un pacte."
- **`notifier_reponse_pacte()`** — trigger `after update of statut` sur `pactes`. Couvre toute la négociation de date (contre-propositions, choix, confirmation, annulation) en déduisant qui notifier uniquement à partir de `old.statut`/`new.statut` (le déroulé est déterministe, voir `bloc_choix_date.dart`/`bloc_reponse.dart`) — pas besoin de `auth.uid()`. Distingue notamment un refus explicite (`old.statut = enAttenteReponse`) d'un abandon faute de date trouvée (`old.statut = enAttenteChoixDateXxx`), avec des textes différents. Exclut explicitement `annuleDoubleAbsence`, qui a sa propre notification. La notification "Pacte confirmé" inclut le nom du restaurant (`restaurants.nom`, via `restaurant_id`).
- **`notifier_nouveau_message()`** — trigger `after insert` sur `messages`. Détermine le destinataire (titulaire ou remplaçant, celui qui n'a pas écrit) en comparant `expediteur_id` à l'id du titulaire du pacte. Inclut le téléphone du remplaçant dans les données de la notification (pour le bouton d'appel au clic) uniquement dans le sens titulaire←remplaçant : dans l'autre sens, `ChatScreen` le récupère déjà via `telephone_titulaire_du_pacte()`.
- **`formater_date_heure_fr(p_date)`** — formatage français ("vendredi 16 octobre à 19h00") écrit à la main (tableaux de jours/mois), Postgres/Supabase n'ayant pas de locale française par défaut.
- **`est_remplacant_du_pacte(p_pacte_id uuid) returns boolean`** — utilisée par la policy SELECT de `pactes` qui laisse un remplaçant voir le pacte concerné (section 7.5). Ne peut pas être un simple `exists (select 1 from remplacants ...)` inline dans la policy : les policies de `remplacants` interrogent `pactes` en retour, ce qui crée une récursion infinie (`infinite recursion detected in policy for relation "pactes"`, code `42P17` — bug rencontré le 27/08, voir section 8). Passer par une fonction `SECURITY DEFINER` casse la boucle, puisqu'elle contourne la RLS de `remplacants` pour cette vérification précise.
- **`telephone_titulaire_du_pacte(p_remplacant_id uuid) returns text`** — permet au bouton d'appel du chat de fonctionner côté remplaçant : renvoie le téléphone du titulaire, uniquement si l'appelant est bien le remplaçant lié à cette ligne (`profil_id = auth.uid()`). Dans l'autre sens (titulaire appelant son remplaçant), aucune fonction n'est nécessaire : le titulaire a déjà ce numéro dans son propre formulaire.
- **`repondre_demande_remplacement(p_remplacant_id uuid, p_accepte boolean)`** (24/09) — la personne sollicitée par "Un imprévu ?" y répond via cette fonction, jamais par une écriture directe. Nécessaire pour deux raisons : (1) en cas d'acceptation, elle doit clôturer les autres demandes en attente du même côté — des fiches `remplacants` qu'un simple remplaçant (propriétaire seulement via `profil_id`, jamais via `cote`) n'a normalement pas le droit de voir/modifier ; (2) garantir qu'**une seule personne peut accepter**, y compris en cas de double acceptation presque simultanée. Cette garantie est assurée par un verrou explicite (`perform ... for update` sur toutes les fiches `remplacants` du côté concerné) posé *avant* de vérifier si la place est déjà prise : une deuxième transaction concurrente attend que la première se termine avant de relire l'état à jour — la seconde relecture voit alors forcément `selectionne = true` déjà posé par la première, et échoue proprement (`place_deja_prise`) au lieu de créer une double acceptation. Voir 7.6.
- **`notifier_demande_remplacement()`** — trigger `after update of demande_statut` sur `remplacants`. Notifie la personne sollicitée dans deux cas seulement : quand une demande lui est envoyée, et quand sa demande en attente est clôturée parce que quelqu'un d'autre a accepté (sans jamais dire qui). Réutilise le type de notification `chat` déjà géré par `NotificationService._gererClicNotification` : au clic, ouvre directement le fil de discussion concerné, où le bandeau de réponse apparaît. Portée volontairement limitée à la personne sollicitée (pas de notification au titulaire quand on lui répond, pour l'instant — voir "Prévu, pas commencé").

## 6. Authentification

- Supabase Auth, email + mot de passe. Confirmation d'email **activée** (`Confirm email` = ON).
- **Site URL** Supabase configuré sur `https://kevinarner.github.io/le_pacte/` (piège initial : reste par défaut sur `http://localhost:3000`, ce qui casse le lien de confirmation reçu par email — voir section 8).
- `AppStore.moi` (`lib/services/app_store.dart`) est l'unique source de vérité de l'identité connectée. Remplacée après un login/signup réussi par `LoginScreen._chargerProfilEtEntrer()`, qui va chercher la ligne `profiles` correspondante.
- **Le mécanisme de simulation « Moi / Mon ami » (`perspectiveMoi`)**, utilisé dans les premières versions pour tester les deux côtés d'un pacte dans un seul navigateur, **a été entièrement retiré**. Il était devenu incompatible avec RLS : la sécurité au niveau ligne résout toujours l'identité *réellement* connectée (`auth.uid()`), quel que soit un éventuel bouton de bascule dans l'UI.

## 7. Cycle de vie d'un pacte

### 7.1 Création

```mermaid
flowchart TD
    K["profiles\nInitiateur — auth.uid()"] -->|initiateur_id| P["pactes\nnouvelle ligne\nstatut = enAttenteChoixDateDestinataire"]
    P -->|restaurant_id| R["restaurants\nAu père Lapin"]
    P -->|"pacte_id, cote = 'initiateur'"| RI["remplacants\nremplaçants de l'initiateur"]
    P -.->|recherche par destinataire_telephone| D{"Un profil existe\navec ce téléphone ?"}
    D -->|oui| E["profiles\nDestinataire"]
    D -->|non| N["destinataire_id = NULL\ndestinataire_nom + destinataire_telephone enregistrés quand même"]
    E -.->|destinataire_id| P
    N -.-> P
```

Si le destinataire n'a pas encore de compte, `destinataire_id` reste `NULL` mais rien n'est perdu : `destinataire_nom` et `destinataire_telephone` sont conservés, et `handle_new_user()` rattachera automatiquement le pacte dès que cette personne créera un compte avec le même numéro.

### 7.2 Acceptation ou refus

```mermaid
flowchart TD
    P0["pactes\nstatut = enAttenteChoixDateDestinataire"] -->|"Le destinataire choisit une date"| U1["UPDATE pactes\ndate_retenue, statut = enAttenteReponse"]
    U1 --> C{"Le destinataire répond"}
    C -->|Accepte| U2["UPDATE pactes\nstatut = confirme"]
    C -->|Refuse| U3["UPDATE pactes\nstatut = annule"]
```

La négociation de date (contre-proposition) est plafonnée à 2 allers-retours (`nombreEchangesDate` / `maxEchangesDate` dans `bloc_choix_date.dart`) ; au-delà, la seule option restante est d'accepter une des dates proposées ou d'annuler.

### 7.3 Accepté, puis délégué à un remplaçant

```mermaid
flowchart TD
    P["pactes\nstatut = confirme"] -->|"« je ne suis plus dispo »\n(vu d'une seule partie)"| F["Formulaire\nremplaçants de cette partie"]
    subgraph SPACE[" "]
        F -->|"INSERT (si pas déjà fait)"| RD["remplacants\ncote = celui de cette partie\npacte_id"]
        RD -->|"Elle en choisit un"| S["UPDATE remplacants\nselectionne = true\nsur la ligne choisie"]
    end
    S -.->|"aucune colonne de pactes lisible par l'app modifiée"| P
    S -.->|"trigger synchroniser_remplacants_caches()"| H["pactes\n20 colonnes cachées\n(jamais lues par l'app)"]
    P -->|"lu par les deux, inchangé"| KV["L'autre partie voit : « Confirmé »\n— identique avant et après"]
    RD -.->|"RLS : côté opposé\nillisible"| X["Invisible pour l'autre partie"]
```

Point clé : la substitution ne touche **aucune colonne lisible par l'app** sur `pactes`. L'autre partie n'a littéralement aucune donnée lui indiquant qu'une substitution a eu lieu — pas seulement un nom caché. Le trigger `synchroniser_remplacants_caches()` écrit bien un historique sur `pactes`, mais dans les 20 colonnes jamais accordées à `authenticated` : cet historique n'existe que pour une consultation manuelle via l'éditeur SQL, jamais pour l'app.

### 7.4 Les deux délèguent : annulation automatique (V1)

Décision V1 (24/08) : faire se rencontrer deux remplaçants qui ne se connaissent pas n'est pas géré pour l'instant — si les deux parties délèguent, le pacte est annulé plutôt que de les mettre en contact.

```mermaid
flowchart TD
    A["remplacants\nCôté A : selectionne = true"] --> T{"trigger\nannuler_si_double_absence()"}
    T -->|"L'autre côté a-t-il déjà\nun remplaçant sélectionné ?"| Q{" "}
    Q -->|non| OK["Rien ne change\npacte reste confirme"]
    Q -->|oui| C["UPDATE pactes\nstatut = annuleDoubleAbsence"]
    C --> M["Message identique aux deux parties :\n« vous avez chacun dû faire appel à un remplaçant »\n— jamais l'identité des remplaçants"]
```

Points volontaires de cette conception :
- **Annulation immédiate**, dès la seconde délégation — pas d'attente d'une échéance J-1.
- **Le message révèle le fait mutuel** (les deux ont délégué) **mais jamais l'identité** des remplaçants — cohérent avec la règle de secret, puisque ce fait-là ne devient vrai, et donc partageable, que lorsqu'il concerne les deux parties à la fois.
- **Pas de notification push pour l'instant** : la partie qui délègue en second voit le changement immédiatement (l'app relit le statut juste après son action) ; l'autre partie le verra en rouvrant l'app. Un vrai push sera branché sur cet événement une fois FCM en place.

### 7.5 Chat titulaire ↔ remplaçants (27/08)

Objectif produit : donner une raison de revenir régulièrement dans l'app, et faire connaître l'app via les remplaçants invités. Un fil de discussion privé s'ouvre automatiquement dès qu'un remplaçant crée un compte — pour **tous** les remplaçants potentiels d'un côté (jusqu'à 5), pas seulement celui finalement délégué.

```mermaid
flowchart TD
    T["Titulaire ajoute un remplaçant\n(téléphone obligatoire)"] --> I{"Ce téléphone correspond-il\nà un compte existant ?"}
    I -->|oui, déjà inscrit| L1["remplacants.profil_id lié\nimmédiatement (trouver_profil_par_telephone)"]
    I -->|non, pas encore inscrit| SMS["Invitation par SMS\n(bouton existant, ouvre l'app SMS)"]
    SMS --> S["La personne crée un compte"]
    S --> L2["handle_new_user() relie profil_id\nsur TOUS les remplacants correspondants"]
    L1 --> C["Conversation utilisable :\nremplacant_id devient la clé du fil"]
    L2 --> C
    C --> A["Le remplaçant voit le pacte sur son accueil\n(nouvelle policy pactes + remplacants)"]
```

Décisions retenues :
- **Un fil par (pacte, remplaçant)**, pas un fil persistant qui traverserait plusieurs pactes — colle au modèle actuel où un remplaçant est ressaisi à chaque pacte (pas de liste de contacts réutilisable).
- **Accessible en permanence** une fois le pacte confirmé, pas seulement au moment de se désister : `MesRemplacantsScreen` (qui remplace l'ancien `ChoisirRemplacantScreen`) permet d'ajouter des remplaçants à tout moment, avant même d'en avoir besoin.
- **Le destinataire renseigne aussi ses remplaçants pour accepter** (`BlocReponse`), symétriquement à l'initiateur qui le fait déjà à la création — sinon son chat resterait vide en pratique.
- Deux policies RLS ont dû être **ajoutées** (pas remplacées) pour que ce flux fonctionne : un remplaçant doit pouvoir voir sa propre fiche `remplacants` et le `pactes` concerné, ce qu'aucune policy existante ne permettait (elles ne couvraient que les titulaires).

### 7.6 "Un imprévu ?" — remplacement avec consentement (24/09)

Décision produit structurante : un Swend reste un Swend même si l'un des deux participants initiaux est remplacé — ce n'est jamais présenté comme "quitter"/"annuler sa participation". Avant cette date, désigner quelqu'un (`selectionne = true`) était une action **instantanée et unilatérale** du titulaire, sans consentement. Ce n'est plus le cas : `selectionne` ne passe à `true` que lorsque la personne sollicitée **accepte**.

```mermaid
flowchart TD
    U["Titulaire : 'Un imprévu ?'\n(ImprevuScreen)"] -->|"Lui demander"| D["remplacants.demande_statut = 'envoyee'\n(update direct, même droit que selectionne avant)"]
    D --> N["notifier_demande_remplacement()\npush + bandeau dans ChatScreen"]
    N --> R{"La personne sollicitée\nrépond, dans ChatScreen"}
    R -->|Refuse| REF["demande_statut = 'refusee'\nreste visible, les autres restent sollicitables"]
    R -->|Accepte| ACC["repondre_demande_remplacement()\nSECURITY DEFINER, verrouille le côté"]
    ACC --> CHK{"Quelqu'un d'autre\na-t-il déjà accepté ?"}
    CHK -->|non| OK["selectionne = true, demande_statut = 'acceptee'\n+ clôture toutes les autres 'envoyee' de ce côté"]
    CHK -->|oui, course perdue| LOSE["exception 'place_deja_prise'\ndemande_statut = 'cloturee' sur cette fiche"]
    OK -.->|"aucune colonne lisible par l'autre partie modifiée"| INVIS["Confidentialité : identique à 7.3,\nrien de visible pour l'autre participant"]
```

Points clés :
- **Plusieurs demandes actives en parallèle** sont explicitement permises (pas de flow séquentiel) : l'utilisateur peut solliciter Kevin puis, sans attendre sa réponse, solliciter aussi Camille. Chaque fiche `remplacants` porte son propre `demande_statut`, indépendamment des autres.
- **Une seule personne peut effectivement accepter** — garanti côté base par `repondre_demande_remplacement()` (section 5), pas seulement par l'interface. Testé par construction : le verrou (`for update`) sérialise deux acceptations concurrentes, la seconde échoue proprement.
- **Confidentialité inchangée vis-à-vis de l'autre participant** : le mécanisme réutilise exactement `selectionne`, déjà invisible pour l'autre côté (7.3) — aucune colonne lisible par l'app n'est touchée par une demande en cours ni par une acceptation.
- **Toutes les personnes prévues refusent** → `ImprevuScreen` propose d'annuler le Swend, en réutilisant `PacteRepository.mettreAJourStatut(pacteId, StatutPacte.annule)` (déjà utilisé par `BlocChoixDate`/`BlocReponse`) — aucune nouvelle logique d'annulation. **L'annulation de la réservation du restaurant n'est pas gérée** : le fonctionnement définitif de la réservation n'est pas encore stabilisé (voir "Prévu, pas commencé").
- **Réponse dans `ChatScreen`**, pas un nouvel écran : un bandeau apparaît en haut du fil, uniquement pour la personne sollicitée (`remplacants.profil_id = moi`), avec `[Accepter]`/`[Refuser]`. Une fois acceptée, le bandeau affiche aussi la date, l'heure et le restaurant (`PacteRepository.pacteDuRemplacant()`, RLS déjà permissive via `est_remplacant_du_pacte()`).
- **`MesRemplacantsScreen`** ("Personnes de confiance") : le bouton "Le/la désigner" (instantané) est retiré, remplacé par "Lui demander" (même mécanisme que `ImprevuScreen`) — il n'existe donc plus qu'une seule façon de devenir "la personne qui prend la place", toujours consentie. `BlocPresence` ("EN CAS D'IMPRÉVU") n'a nécessité **aucune modification** : sa logique affichait déjà quelqu'un uniquement si `selectionne = true`, ce qui reste vrai, juste avec une condition supplémentaire en amont (l'accord de la personne).

## 8. Bugs rencontrés et corrigés (pour ne pas les refaire)

| Symptôme | Cause | Correction |
|---|---|---|
| "Impossible de joindre le serveur" au login/signup, aucune requête réseau visible | `MissingPluginException` sur `shared_preferences` en web — enregistrement de plugin périmé après ajout de `supabase_flutter` | `flutter clean` + `flutter pub get` + rebuild |
| Lien de confirmation d'email renvoie vers `localhost:3000` et une page d'erreur | Site URL Supabase resté sur sa valeur par défaut | Authentication → URL Configuration → Site URL = URL de prod, + ré-inscription pour un lien frais |
| Écran d'accueil bloqué sur un chargement infini après connexion | RLS activée sur `restaurants` sans aucune policy de lecture → 406 de Supabase, et aucune gestion d'erreur côté app pour l'afficher | Policy `using (true)` sur `restaurants` + gestion d'erreur explicite (message + bouton Réessayer) dans `AccueilScreen`/`CreerPacteScreen` |
| La policy initiale de `remplacants` laissait chaque partie voir les remplaçants de l'autre | La condition RLS vérifiait "ce pacte m'appartient" sans vérifier "ce côté est le mien" | Policy réécrite pour vérifier `cote = 'initiateur' and initiateur_id = auth.uid()` (et son symétrique) |
| `PostgrestException: infinite recursion detected in policy for relation "pactes"` (code `42P17`) au chargement de l'accueil | La policy laissant un remplaçant voir le pacte concerné interrogeait `remplacants`, dont les policies interrogent `pactes` en retour — boucle infinie | Passer par la fonction `SECURITY DEFINER` `est_remplacant_du_pacte()`, qui contourne la RLS de `remplacants` pour cette vérification et casse la boucle |
| Le destinataire d'un pacte ne voyait pas la proposition, alors qu'elle avait bien été créée | Deux comptes différents avaient le même numéro de téléphone (aucune contrainte ne l'empêchait) ; `trouver_profil_par_telephone()` (`... limit 1`) a résolu vers le mauvais profil, donc `destinataire_id` ne pointait pas vers le bon compte | Index unique partiel sur `profiles.telephone` (`where telephone <> ''`) — empêche désormais deux comptes de partager un numéro, avec un message clair à l'inscription si ça arrive |
| `PostgrestException: new row violates row-level security policy for table "pactes"` (code 42501) à la création d'un pacte, alors que l'utilisateur était bien connecté | Plusieurs onglets du même navigateur connectés à des comptes différents : la session Supabase est partagée via le stockage local, se connecter ailleurs remplace silencieusement celle utilisée par les autres onglets, sans que `AppStore.moi` ne s'y resynchronise — RLS a bloqué à raison une écriture avec un `initiateur_id` qui ne correspondait plus à la session réelle | `RootShell` écoute `onAuthStateChange` et force une reconnexion avec un message clair dès que la session change sous ses pieds |
| Page blanche au chargement (28/08), puis `PlatformException(channel-error, Unable to establish connection on channel: "...FirebaseCoreHostApi.initializeCore")` une fois le crash rattrapé | Même famille que le bug `shared_preferences` ci-dessus, avec `firebase_core`/`firebase_messaging` cette fois : le fichier généré `web_plugin_registrant.dart` (celui qui appelle `XxxWeb.registerWith(registrar)` pour chaque plugin) n'avait jamais été régénéré depuis leur ajout — `FirebaseCoreWeb` n'y figurait pas, donc jamais enregistré, donc tree-shaké du bundle final. Diagnostiqué en reproduisant en local avec Chromium headless (Playwright) + interception réseau vers une copie locale de CanvasKit, le sandbox n'ayant pas accès à gstatic.com | `flutter clean` avant le rebuild force la régénération de ce fichier. **Retenu pour la suite : toujours faire `flutter clean` après l'ajout d'un nouveau plugin avec une implémentation web**, avant même de tester — ce bug s'est maintenant produit deux fois pour la même raison |
| `[firebase_messaging/failed-service-worker-registration] ... 404 ... firebase-messaging-sw.js` au moment d'obtenir le token FCM (web) | `firebase_messaging_web` cherche le service worker à la racine du domaine par défaut, alors que l'app est servie dans le sous-dossier `/le_pacte/` (GitHub Pages) | Passer `serviceWorkerScriptPath: 'firebase-messaging-sw.js'` à `getToken()` — résolu relativement à `<base href>` |
| `PostgrestException ... violates check constraint "device_tokens_plateforme_check"` en enregistrant le token | La contrainte n'autorisait que `'ios'`/`'android'`, pas `'web'` | Contrainte élargie à `'ios','android','web'` ; côté Dart, `defaultTargetPlatform.name` normalisé en minuscules (il renvoie `'iOS'` avec un O majuscule, qui aurait échoué pareil sur un vrai appareil iOS) |
| `AbortError: Failed to execute 'subscribe' on 'PushManager' ... no active Service Worker` en enregistrant le token FCM (web), même après les corrections ci-dessus | Le service worker interne de Flutter (`flutter_service_worker.js`, déprécié, cache hors-ligne) et celui de FCM (`firebase-messaging-sw.js`) partagent le même scope (même dossier) : l'enregistrement/mise à jour permanente de celui de Flutter empêchait celui de FCM de rester actif | `web/flutter_bootstrap.js` personnalisé (repris du template par défaut de Flutter, mécanisme découvert en lisant le code source de `flutter_tools`) qui appelle `_flutter.loader.load({})` sans `serviceWorkerSettings` — désactive le SW interne de Flutter, qu'on n'utilise pas de toute façon. En complément : le SW de FCM est maintenant aussi enregistré dès le chargement de la page (`web/index.html`) plutôt qu'au moment de la connexion, pour lui laisser le temps de s'activer, avec une nouvelle tentative automatique en cas d'échec transitoire |
| Le bouton "Accepter le pacte" restait grisé même une fois les 2 remplaçants du destinataire entièrement remplis (29/08) | Dans `RemplacantsForm`, les champs téléphone/email appelaient `r.telephone = v` mais oubliaient `widget.onChanged()` (contrairement à prénom/nom) : `BlocReponse` ne se reconstruisait donc pas après la saisie du téléphone, alors que `estRempli` (et donc le bouton) en dépend | `widget.onChanged()` ajouté aux deux champs |
| `MesRemplacantsScreen` affichait "N'a pas encore rejoint l'application" pour un remplaçant dont le compte était pourtant bien lié en base (25/09, repéré en testant "Un imprévu ?") | Contrairement à `ImprevuScreen`, cet écran affichait uniquement `widget.cotePacte.listeRemplacants` tel que chargé en mémoire au moment où `DetailPacteScreen` a ouvert le pacte, sans jamais se resynchroniser à l'ouverture — un `profil_id` lié après ce chargement restait donc invisible tant que l'app n'était pas rechargée entièrement | Ajout de `_rafraichir()` dans `initState()` : recharge la liste depuis le serveur et met à jour en place les fiches déjà enregistrées (par `id`), sans toucher aux nouvelles fiches en cours de saisie (sans `id`) |

## 9. État actuel

**Fait et déployé :**
- Authentification réelle (Supabase Auth), création de profil automatique, rattachement automatique par téléphone.
- Cycle de vie complet d'un pacte : création, négociation de date (max 2 allers-retours), acceptation/refus, délégation à un remplaçant, statuts `confirme`/`maintenu`/`annule`/`annuleDoubleAbsence`.
- Annulation automatique si les deux parties délèguent leur présence (V1 — pas de mise en contact entre remplaçants).
- Chat privé en temps réel entre un titulaire et chacun de ses remplaçants, dès que ceux-ci ont un compte — ouverture automatique par rattachement téléphone, écran permanent pour gérer sa liste et déléguer.
- Confidentialité par côté appliquée à la fois par RLS (lignes) et par grants de colonnes (historique permanent invisible à l'app).
- **Notifications push (FCM), de bout en bout** (28-29/08) : projet Firebase (`le-pacte-e6c17`, apps Android/iOS/Web), intégration client (`lib/services/notification_service.dart` : permission, token, sauvegarde dans `device_tokens`, bannière in-app si l'app est au premier plan), Edge Function d'envoi (`supabase/functions/send-notification`, API FCM v1 via compte de service), déclencheurs Postgres sur les 4 événements (nouveau pacte, réponse à un pacte avec tous ses sous-cas, message de chat, double absence — voir section 5), et routage au clic sur une notification vers le bon pacte/chat (`navigatorKey`, `PacteRepository.pacteParId()`). Vérifié en conditions réelles (notification système reçue). Plusieurs bugs corrigés au passage (voir section 8).
- **Refonte navigation/UX** (29/08), palette pêche/bleu ardoise/crème (voir `AppColors` dans `lib/theme/app_theme.dart` — couleur d'erreur `erreur` distincte de l'accent). Plus de barre de navigation basse : après connexion, un **menu principal** (`lib/screens/root/menu_principal_screen.dart`) donne accès à quatre sections — Mes Pactes, Messagerie, Profil, Nous contacter — chacune poussée via `Navigator.push` et ramenant au menu via le logo dans son `AppBar` (`Navigator.pop`). Onglet **Messagerie** (`lib/screens/messagerie/messagerie_screen.dart`) qui regroupe tous les fils de discussion où je suis impliqué, titulaire ou remplaçant, via `PacteRepository.mesFilsDeDiscussion()` — une seule requête sur `remplacants` suffit : la RLS existante renvoie déjà l'union "mes propres remplaçants" et "mes fiches de remplaçant" pour un même utilisateur ; chaque fil affiche aussi la date et le restaurant du pacte concerné (03/09). Pas de suivi lu/non-lu pour cette première version (décision explicite). Le bouton "+ Nouveau pacte" devient une icône flottante (mains détourées, réutilise les PNG du logo — `assets/images/`). **Création de pacte scindée en 3 étapes** (avec qui / où et quand / remplaçants) avec indicateur de progression. **Profil enrichi** : pactes réalisés, remplacements effectués (`PacteRepository.nombreRemplacementsEffectues()`), taux de fiabilité (part des pactes `confirme`/`maintenu` parmi tous les pactes arrivés à un statut terminal). L'animation d'ouverture "boule de papier" prévue dans la maquette n'est pas encore intégrée : en attente d'une nouvelle image de la part de l'utilisateur.
- **Renommage en "Pakt", "Nous contacter", sélection de contacts, vraies modifications de compte** (03/09) :
  - "Le Pacte" remplacé par "Pakt" partout dans l'app (login, titre, hub, invitations SMS, `web/index.html`, `web/manifest.json`, labels Android/iOS) — les identifiants de package/URL (`le_pacte`, `com.kevinarner.le_pacte`/`lePacte`) sont volontairement inchangés, ce sont des identifiants techniques, pas du texte affiché.
  - Logo (mains entrecroisées) ajouté sur l'écran de connexion.
  - Nouvelle catégorie **Nous contacter** sur le hub : suggestion de restaurant (`suggestions_restaurant`, section 4) et formulaire "Autres" (`messages_contact`, section 4 — pas encore de vrai envoi d'email, boîte de contact pas encore créée). Le lien "ici" de l'étape "Où et quand ?" de la création de pacte ouvre directement le formulaire de suggestion, avec retour à l'étape en cours via le bouton retour standard.
  - Étapes "Avec qui ?" et "Tes remplaçants" (`lib/widgets/remplacants_form.dart`) : champ email retiré, remplacé par un bouton "Choisir dans mes contacts" quand la Contact Picker API du navigateur est disponible (`ContactPickerService.disponible`) — **Android + Chrome uniquement à ce jour** (ni iOS Safari, ni desktop) ; ailleurs le bouton est simplement absent, la saisie manuelle reste l'unique option. Implémenté via `dart:js_interop`/`dart:js_interop_unsafe` plutôt que `package:web`, cf. section 2.
  - **Profil → Mes informations** (`lib/screens/profil/mes_informations_screen.dart`) : Nom (non modifiable), Téléphone/Email/Mot de passe affichent la vraie valeur et un bouton "Modifier" avec persistance réelle (`lib/services/profil_repository.dart`) — téléphone via un `update` direct sur `profiles` (RLS déjà permissive, "chacun modifie sa propre ligne", contrainte d'unicité déjà en place, même message d'erreur qu'à l'inscription en cas de doublon), email et mot de passe via `Supabase.auth.updateUser()` (le changement d'email nécessite de cliquer le lien de confirmation envoyé par Supabase avant de prendre effet, comme pour l'inscription).
- **Renommage en "Swend"** (23/09) : "Pakt" remplacé par "Swend" partout dans l'app (titre, hub, invitations SMS, `web/index.html`, `web/manifest.json`, labels Android/iOS) — mêmes identifiants de package/URL volontairement inchangés qu'au renommage précédent (voir "Prévu, pas commencé"). Sur l'écran de connexion et le hub, le texte "Pakt"/"Swend" est remplacé par une image du logotype manuscrit fourni par l'utilisateur (`assets/images/logo_swend_wordmark.png`, fond rendu transparent, encre recolorée pour matcher `AppColors.texte`) — **wordmark explicitement temporaire**, une version définitive suivra. Un nom de domaine `swend.fr` et un site vitrine statique (repo séparé `swend-site-vitrine`, hébergé sur GitHub Pages) existent déjà pour la marque, indépendamment de cette app.
- **Refonte UX du hub : "chaque Swend est un objet autonome"** (23/09). Décision produit structurante : la messagerie n'est plus une section indépendante de l'app — `lib/screens/messagerie/messagerie_screen.dart` a été supprimé, il n'y a plus d'écran listant tous les fils de discussion tous pactes confondus. Chaque conversation est désormais rattachée à son pacte via `BlocPresence` sur `DetailPacteScreen` (voir la passe vocabulaire ci-dessous pour son habillage actuel).
  - Hub (`menu_principal_screen.dart`) restructuré selon la hiérarchie "quel est mon prochain Swend ? est-ce que quelque chose nécessite mon attention ? comment créer/retrouver mes Swends ?" : carte "TON PROCHAIN SWEND", puis une éventuelle carte de notification de message ("{nom} vous a écrit"), puis un bouton `FilledButton` très visible **"Créer un Swend"** (accès direct à `CreerPacteScreen` depuis le hub), puis la tuile "Mes Swends" (`X à venir`, badge si une action est requise), puis "Profil" en simple ligne discrète (plus de tuile-carte). "Nous contacter" n'apparaît plus sur le hub : déplacé dans Profil sous une ligne "Aide / Nous contacter".
  - **Notification de nouveau message sans vrai suivi lu/non-lu** : `FilDeDiscussion` gagne un champ `dernierMessageDeMoi` (comparaison de `expediteurId` avec l'utilisateur courant, calculé dans `PacteRepository.mesFilsDeDiscussion()`) ; le hub affiche le fil le plus récent dont le dernier message n'est pas de moi. **Ce n'est pas un vrai lu/non-lu** : aucun état de lecture n'est persisté, donc la carte peut réapparaître à chaque ouverture du hub tant qu'on n'a pas répondu dans ce fil précis — limitation connue, acceptée pour cette itération (un vrai suivi demanderait une colonne/table de "dernière lecture", pas construite ici).
- **Suppression d'un Swend depuis "Mes Swends"** (23/09) : sur `AccueilScreen`, chaque carte de pacte est balayable (`Dismissible`, swipe de droite à gauche) avec confirmation (`AlertDialog` destructif) avant suppression définitive. Côté base, une fonction `SECURITY DEFINER` `supprimer_pacte(p_pacte_id uuid)` (migration livrée à l'utilisateur, à exécuter manuellement dans le SQL Editor Supabase) vérifie que l'appelant est bien l'initiateur ou le destinataire du pacte puis supprime en cascade `messages` → `remplacants` → `pactes` — nécessaire car les remplaçants sont cloisonnés par côté via RLS et un DELETE client classique ne pourrait pas franchir cette frontière pour l'autre côté. Exposée côté app via `PacteRepository.supprimerPacte(String pacteId)`.
- **Passe de cohérence vocabulaire "Swend"** (23/09) : suite explicite pour généraliser à toute l'interface visible le vocabulaire "simple, humain, légèrement mystérieux, chaleureux, jamais administratif" et éviter les mots "Pacte", "relais" et "remplaçant" — texte uniquement, modèle de données et noms de classes/routes inchangés (`Pacte`, `Remplacant`, `pactes`, `remplacants`, `RemplacantsForm`, `MesRemplacantsScreen`, `BlocPresence` restent tels quels en interne).
  - "Pacte avec X" → "**Swend avec X**" partout où c'était affiché (cartes "Mes Swends", titre `DetailPacteScreen`, wizard de création "Nouveau Swend" / "Envoyer le Swend", boutons "Accepter/Refuser le Swend", "Annuler le Swend", messages d'erreur, textes d'invitation SMS, stat "Swends réalisés" du profil).
  - Badge "Confirmé" → "**Scellé**" (voir aussi la passe "badges orientés action" ci-dessous, qui remplace complètement l'ancien badge générique "Date à confirmer").
  - `BlocPresence` : section "Mon relais" → "**EN CAS D'IMPRÉVU**", qui explique la fonction plutôt que de nommer le rôle ("Peut prendre votre place" / bouton "Écrire à {prénom}" / lien "Modifier cette personne" si quelqu'un est désigné ; "Choisissez une personne de confiance" / bouton "Choisir une personne" sinon). `MesRemplacantsScreen` (accessible depuis ces boutons) renommée "Personnes de confiance" dans l'UI, ainsi que `RemplacantsForm` ("Ajouter une personne", "Personne {n}") et les textes d'invitation SMS associés — même traitement dans le wizard de création et `BlocReponse`/`BlocEpilogue` (`BlocCascade` a depuis été supprimé, voir plus bas).
  - Notification de message sur le hub : le texte fixe "À propos de votre Swend" est remplacé par un contexte dynamique **"Swend avec {autre partie} · {date} à {heure}"**. Nouveau champ `FilDeDiscussion.autrePartieNom` (calculé dans `PacteRepository.mesFilsDeDiscussion()` à partir de `cote` et des noms initiateur/destinataire du pacte) — distinct de `nomInterlocuteur`, qui peut être la personne de confiance plutôt que l'autre titulaire.
  - Carte "TON PROCHAIN SWEND" élargie à 82 % de la largeur disponible (`FractionallySizedBox`), centrée, sans changer son style.
  - FAB (icône mains) supprimé sur `AccueilScreen` : la création se fait déjà depuis le bouton "Créer un Swend" du hub ; le texte d'état vide de cet écran a été adapté en conséquence.
- **Badges de statut orientés action** (23/09) : le badge d'un Swend en négociation ne décrit plus l'état technique ("Date à confirmer") mais qui doit agir — `lib/theme/app_theme.dart` gagne `pacteEstMonTour(StatutPacte, bool jeSuisInitiateur)` (logique unique de "à qui le tour", déjà présente en double dans `DetailPacteScreen` et le hub — celle du hub, `_actionRequise`, a été récrite pour l'appeler au lieu de dupliquer les mêmes comparaisons ; celle de `DetailPacteScreen`, `estMonTourDate`/`estMonTourReponse`, distingue en plus *quel type* d'action — choix de date vs réponse — pour savoir quel bloc afficher, donc n'a pas été fusionnée) et `statutAffichagePourMoi(StatutPacte, {jeSuisInitiateur, autrePrenom})`, qui renvoie un libellé + un style (`StatutAffichage`) : **"À vous de répondre"** (fond `AppColors.accent` plein, texte blanc — seul badge volontairement plus visible que les autres, sans rouge/alerte) quand c'est mon tour, sinon **"En attente de {prénom de l'autre}"** (style discret, transparent + contour, déjà utilisé pour les statuts de négociation) ; "Scellé" et les statuts terminaux (`Maintenu ✅`, `Annulé ✗`) inchangés. Utilisé par `AccueilScreen._cardPacte` et le badge en tête de `DetailPacteScreen`. Le prénom est simplement le premier mot de `nomTitulaire` (aucune colonne prénom séparée n'existe côté pacte — introduire un vrai champ prénom n'était pas nécessaire ici).
  - **Tri de "Mes Swends"** : priorité — voir la micro-itération ci-dessous pour l'ordre actuel (mon tour → scellé → j'attends l'autre → terminé/annulé) —, puis par `dateRetenue` croissante à l'intérieur de chaque groupe. Pas de sections séparées, un seul tri (`AccueilScreen._trierParPriorite`), calculé une fois après le chargement.
- **Micro-itération UX : ordre, wording, fiche d'un Swend scellé** (23/09).
  - **Ordre de "Mes Swends" revu** : mon tour (0) → **scellé, trié chronologiquement** (1) → j'attends l'autre partie (2, visible mais plus discret qu'un scellé à venir) → terminé/annulé (3). Départage stable par `dateRetenue` puis par `id` si tout est égal (`AccueilScreen._priorite`/`_trierParPriorite`).
  - **Prénom seul, centralisé** : nouvelle fonction `prenomDe(String)` dans `lib/utils/noms.dart` (premier mot d'un nom complet), qui remplace 3 copies du même one-liner (`AccueilScreen`, `DetailPacteScreen`, le hub) — utilisée pour les badges "En attente de {prénom}" et pour la notification de message du hub, qui affiche désormais le prénom de l'autre partie plutôt que son nom complet ("Swend avec David · 13 octobre à 19h00").
  - **Message d'attente reformulé** sur un Swend non scellé (`DetailPacteScreen`, bloc `BlocAttente`) : "En attente du choix de date de X."/"En attente de la réponse de X." remplacés par "{Prénom} peut choisir cette date ou en proposer une autre." (pluriel automatique : "une de ces dates ... d'autres" si plusieurs dates sont proposées) ou "{Prénom} peut accepter ce Swend ou le refuser." — même logique `jAttendsLAutrePartie`/`estMonTourReponse` qu'avant, seul le texte change.
  - **Singulier/pluriel** sur le libellé "Date(s) proposée(s)" du détail (`LigneInfo`), déjà correct sur les cartes "Mes Swends".
  - **Fiche épurée** : suppression de la ligne "Avec X" (redondante avec le titre "Swend avec X"), toujours. Une fois une date retenue (`dateRetenue != null`), elle s'affiche directement sans étiquette "Date :" (les propositions encore en cours gardent leur étiquette "Date(s) proposée(s)", car ce ne sont pas encore *la* date). Le restaurant retenu (`restaurantRetenu`, présent dès la confirmation, y compris pour un Swend `maintenu` ou `annuleDoubleAbsence`) n'affiche plus l'URL brute : son nom en gras, suivi d'un lien "Voir le restaurant ↗" qui réutilise `_reserverLaTable()` (même mécanisme que le bouton "Réserver la table", pas de nouvelle logique).
- **Micro-itération UX : parcours "Créer un Swend"** (23/09) — wording et présentation uniquement, aucune règle métier touchée (`_peutValiderEtape`, minimum de 2 personnes, envoi du pacte inchangés).
  - Étape 1 "Avec qui ?" : phrase d'intro ajoutée, texte SMS reformulé en "Cette personne n'a pas encore Swend ?" (même reformulation appliquée dans `RemplacantsForm`, partagée avec l'étape 3, `MesRemplacantsScreen` et `BlocReponse`).
  - Étape 2 "Où et quand ?" → **"Quand et où ?"**, contexte discret "Swend avec {prénom}" ajouté (comme à l'étape 3), type de repas en `SegmentedButton` au lieu de deux `RadioListTile` verticaux (même état `type`, juste un autre widget), texte des dates proposées reformulé dynamiquement ("Propose une ou plusieurs dates.\n{Prénom} choisira celle qui lui convient."), carte restaurant alignée sur le même style que la fiche d'un Swend scellé (en-tête "RESTAURANT PROPOSÉ", lien "Voir le restaurant ↗" au lieu de l'URL brute).
  - Étape 3 "Tes personnes de confiance" → **"En cas d'imprévu"** (même intitulé que la section correspondante sur la fiche d'un Swend confirmé), texte reformulé "Choisis au moins 2 personnes qui pourraient prendre ta place si nécessaire.\n{Prénom} ne verra jamais cette liste."
  - Le prénom du destinataire vient directement de `prenomDestinataireController` (champ Prénom dédié dès l'étape 1, pas de découpage d'un nom complet nécessaire) — nouveau getter `_prenomDestinataire`.
  - Barre de progression sortie de la `ListView` et épinglée en haut de l'écran (`Column` + `Expanded(ListView(...))`) : elle ne défile plus hors champ sur l'étape 3, plus longue (jusqu'à 5 personnes de confiance) — c'était la seule cause de son "absence" perçue, la logique des segments actifs (`i <= etape`) n'avait pas changé.
  - `DatesForm` (partagé avec la contre-proposition de date sur un Swend en négociation, `bloc_choix_date.dart`) condensée en une seule ligne par date (`ListTile` avec le sélecteur d'horaire et le bouton de suppression en `trailing`, au lieu d'une deuxième ligne "Horaire :" séparée) — même comportement (tap sur la date pour la changer, menu déroulant pour l'horaire, croix pour retirer si au-dessus du minimum), juste plus compact.
- **Correctif glyphe cassé** (24/09) : le caractère "↗" utilisé pour "Voir le restaurant ↗" (fiche d'un Swend scellé et carte restaurant de l'étape 2 du wizard) n'existe pas dans la police Georgia de l'app et s'affichait comme un carré vide — remplacé par `Icons.north_east`. Trouvé en faisant réellement tourner l'app dans un navigateur (voir méthode ci-dessous), pas en relisant le code.
- **Reformulation des SMS d'invitation** (24/09) : nouveau texte pour les deux SMS envoyés depuis le parcours de création — invitation au Swend (`CreerPacteScreen._inviterParSms`) et invitation d'une personne de confiance (`RemplacantsForm._inviterParSms`, partagé avec "Personnes de confiance" et l'écran d'acceptation). Contenu uniquement : mécanisme d'envoi (`sms:...?body=...`), numéro et lien inchangés ; le second SMS ne mentionne plus de date/heure (`_phraseDate` devenue inutile, retirée). Les deux messages ont été vérifiés en interceptant réellement l'appel `launchUrl` dans un navigateur pour lire le texte final généré, pas en relisant le code.
- **Méthode de vérification visuelle** (24/09, réutilisable) : pour confirmer qu'un changement est bien visible/correct sans compte de test, un point d'entrée Flutter temporaire (`lib/main_preview.dart`, jamais commité) lance l'écran ciblé directement (sans connexion), avec au besoin un stub local de `PacteRepository.restaurant()` pour éviter l'appel réseau Supabase (bloqué depuis cet environnement). Servi en local (`flutter build web -t lib/main_preview.dart --no-web-resources-cdn` + `http-server`) et piloté avec Playwright/Chromium (déjà installés) pour remplir les champs, avancer les étapes et capturer des captures d'écran ou intercepter `window.open` (pour lire l'URL `sms:` sans lancer d'app SMS réelle). Toujours nettoyé (fichier supprimé, stub annulé) avant tout commit.
- **Suppression de la simulation "garde-fou anti-désistement"** (24/09) : `BlocCascade` et son fichier (`lib/screens/detail_pacte/bloc_cascade.dart`) supprimés de `DetailPacteScreen` à la demande de l'utilisateur — c'était un outil de test temporaire (boutons "Simuler J-1..."), pas une fonctionnalité produit. Les vraies relances automatiques J-7/J-3/J-1 restent à construire proprement plus tard (voir "Prévu, pas commencé").
- **"Un imprévu ?" — remplacement avec consentement** (24/09), fonctionnalité centrale du produit. Détail complet en section 7.6 et 5. Résumé : nouvelle colonne `remplacants.demande_statut` (`envoyee`/`refusee`/`cloturee`/`acceptee`) ; nouvel écran `ImprevuScreen` (accessible depuis un lien discret "Un imprévu ?" sous `BlocPresence`, uniquement sur un Swend `confirme`) qui liste les personnes de confiance prévues avec un bouton "Lui demander" par personne (aucune priorité/ordre entre elles, plusieurs demandes actives en parallèle) ; la personne sollicitée répond depuis un bandeau `[Accepter]`/`[Refuser]` ajouté en haut de `ChatScreen` ; l'acceptation passe par la fonction `SECURITY DEFINER` `repondre_demande_remplacement()`, seule à garantir qu'une seule personne peut effectivement prendre la place (verrou en base, pas seulement côté interface) et à clôturer automatiquement les autres demandes en attente ; notification push à la personne sollicitée (envoi + place prise par quelqu'un d'autre) via `notifier_demande_remplacement()`. `MesRemplacantsScreen` ("Personnes de confiance") utilise désormais le même mécanisme de demande ("Lui demander" au lieu de "Le/la désigner" instantané) — il n'existe donc plus qu'une seule façon de devenir "la personne qui prend la place", toujours consentie. Confidentialité vis-à-vis de l'autre participant inchangée (7.3) : rien de nouveau n'est lisible par l'app côté autre partie. Si toutes les personnes prévues refusent, `ImprevuScreen` propose d'annuler le Swend en réutilisant `mettreAJourStatut(pacteId, StatutPacte.annule)` — **l'annulation de la réservation du restaurant n'est pas gérée**, le fonctionnement définitif de la réservation n'étant pas encore stabilisé. Un bug de layout réel (un `OutlinedButton` sans style local héritait d'une largeur minimale infinie du thème global, écrasant le nom de la personne dans la carte) a été trouvé et corrigé en faisant tourner l'écran dans un navigateur, pas en relisant le code — voir méthode de vérification visuelle ci-dessus.
- **Correctifs suite au premier test réel de "Un imprévu ?"** (25/09) :
  - `MesRemplacantsScreen` affichait "N'a pas encore rejoint l'application" pour une personne dont le compte était pourtant bien lié en base : l'écran ne se resynchronisait jamais avec le serveur à l'ouverture, contrairement à `ImprevuScreen`. Ajout de `_rafraichir()` dans `initState()` (voir section 8). **Complété le jour même** : ce premier correctif ne faisait que mettre à jour/ajouter, jamais supprimer — une fiche déjà enregistrée mais depuis supprimée côté serveur (Swend supprimé, ou autre manipulation, avec l'onglet resté ouvert sur l'ancien état) continuait donc de s'afficher indéfiniment, avec des champs figés (ex. "A accepté ✓" alors que la ligne n'existe plus). `_rafraichir()` retire maintenant localement toute fiche avec un `id` absente de la réponse fraîche du serveur.
  - **Indicateur "Déjà sur Swend" en direct pendant la saisie d'un numéro** (étape 1 "Avec qui ?" de `CreerPacteScreen`, et chaque personne dans `RemplacantsForm`, partagé avec "Personnes de confiance" et l'étape 3 du wizard) : jusque-là, le bloc "Cette personne n'a pas encore Swend ? → Inviter par SMS" s'affichait systématiquement, sans jamais vérifier si le numéro tapé correspondait déjà à un compte existant — repéré par l'utilisateur en testant avec un numéro qu'il savait pourtant déjà inscrit. Le numéro est maintenant revérifié via `PacteRepository.trouverProfilParTelephone()` (RPC déjà existante, jusque-là seulement appelée côté serveur à l'enregistrement) après un court délai sans frappe (`Timer` de 500 ms, pour ne pas interroger le serveur à chaque caractère) ; si un compte est trouvé, le bloc SMS est remplacé par "✓ Déjà sur Swend". Purement indicatif : la vraie liaison `profil_id` continue de se faire à l'enregistrement, inchangée.

**Prévu, pas commencé :**
- Envoi d'un vrai email pour le formulaire de contact "Autres" (boîte mail dédiée + prestataire d'envoi à choisir) — les messages sont pour l'instant uniquement stockés dans `messages_contact`.
- Préférences de notifications depuis le profil — ligne encore non fonctionnelle (`"Bientôt disponible"`).
- Animation d'ouverture "boule de papier" à la connexion (en attente de l'image).
- Analytics (PostHog).
- Plusieurs restaurants au choix (un seul en dur aujourd'hui) ; les suggestions reçues via `suggestions_restaurant` sont pour l'instant consultées manuellement, pas encore intégrées à une liste de choix.
- Upload réel des photos de profil/remplaçants (actuellement local au navigateur, jamais envoyé à Supabase Storage).
- Vraies relances automatiques J-7/J-3/J-1 (garde-fou anti-désistement) — la simulation manuelle par boutons (`BlocCascade`) a été retirée le 24/09 en attendant une implémentation propre, voir section "Fait et déployé".
- Identifiants Firebase/stores/package non renommés en cohérence avec "Swend" (décision volontairement reportée) : iOS `com.kevinarner.lePacte`, Android `com.kevinarner.le_pacte`, projet Firebase `le-pacte-e6c17`.
- Wordmark "Swend" définitif — celui en place aujourd'hui est une première ébauche explicitement temporaire fournie par l'utilisateur.
- `ios/` et `android/` sont scaffoldés (`flutter create`) mais l'app n'a jamais été publiée sur aucun store.
- Vrai suivi lu/non-lu des messages (la notification "{nom} vous a écrit" sur le hub est une approximation sans état persisté, voir section 9).
- Annulation de la réservation du restaurant quand un Swend est annulé faute de personne disponible ("Un imprévu ?", section 7.6) — le fonctionnement définitif de la réservation n'est pas encore stabilisé, la V1 se contente d'annuler le Swend lui-même.
- Notification au titulaire quand une personne accepte ou refuse une demande "Un imprévu ?" (il le voit en rouvrant `ImprevuScreen`, pas de push pour l'instant — portée volontairement limitée à la personne sollicitée, voir section 5).
- Scénario où deux personnes de remplacement pourraient finalement dîner ensemble (double substitution) — explicitement hors V1 pour "Un imprévu ?".
