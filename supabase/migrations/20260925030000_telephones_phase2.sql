-- Chantier téléphone — PHASE 2 : unicité canonique, rattachements côté
-- serveur, numéro figé, garde-fous. À exécuter APRÈS telephones_phase1.sql.
-- Sûre à ré-exécuter. Ne modifie aucune donnée utilisateur existante, à
-- une exception près : le rattrapage (étape 8) remplit des liens
-- `profil_id` / `destinataire_id` VIDES quand un compte correspond sans
-- ambiguïté — jamais d'écrasement.
--
-- Principes (décidés le 25/09) :
--  * profile_id = identité canonique ; telephone_e164 = clé de
--    rapprochement (identité provisoire d'un contact sans compte) ;
--  * tous les rattachements sont calculés par la base, jamais repris du
--    client (destinataire_id et profil_id envoyés par l'app sont ignorés) ;
--  * un compte par numéro réel ; numéro de compte figé en V1 ;
--  * un participant du Swend ne peut pas être personne de confiance ;
--  * mobiles uniquement, outre-mer pris en charge (normaliser_telephone,
--    phase 1) ; plus aucune recherche de compte par numéro depuis l'app.
--
-- Codes d'erreur renvoyés à l'app : telephone_invalide,
-- personne_est_participant, personne_deja_prevue,
-- destinataire_est_initiateur, telephone_fige, modification_interdite.

-- 0. Pré-requis : la phase 1 doit avoir été exécutée ----------------------

do $$
begin
  if to_regprocedure('public.normaliser_telephone(text)') is null
     or not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'remplacants'
                      and column_name = 'telephone_e164') then
    raise exception 'Exécuter telephones_phase1.sql avant cette phase.';
  end if;
end $$;

-- 1. Sauvegarde fraîche (nouvelles tables horodatées à chaque exécution) --

do $$
declare
  suffixe text := to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS_US');
begin
  execute format('create table sauvegarde.%I as select id, telephone, telephone_e164 from public.profiles',
    'phase2_profiles_' || suffixe);
  execute format('create table sauvegarde.%I as select id, pacte_id, cote, telephone, telephone_e164, profil_id, selectionne, demande_statut from public.remplacants',
    'phase2_remplacants_' || suffixe);
  execute format('create table sauvegarde.%I as select id, initiateur_id, destinataire_id, destinataire_telephone, destinataire_telephone_e164 from public.pactes',
    'phase2_pactes_' || suffixe);
  execute format($q$create table sauvegarde.%I as
      select p.proname::text as nom, pg_get_functiondef(p.oid) as definition
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('handle_new_user', 'trouver_profil_par_telephone',
        'telephone_titulaire_du_pacte', 'normaliser_nouveau_remplacant', 'ajouter_et_demander_remplacement')
      union all
      select 'index ' || indexname, indexdef from pg_indexes
      where schemaname = 'public' and tablename in ('profiles', 'remplacants', 'pactes')$q$,
    'phase2_fonctions_' || suffixe);
  execute format('alter table sauvegarde.%I enable row level security', 'phase2_profiles_' || suffixe);
  execute format('alter table sauvegarde.%I enable row level security', 'phase2_remplacants_' || suffixe);
  execute format('alter table sauvegarde.%I enable row level security', 'phase2_pactes_' || suffixe);
  execute format('alter table sauvegarde.%I enable row level security', 'phase2_fonctions_' || suffixe);
  raise notice 'Sauvegarde : tables sauvegarde.phase2_*_%', suffixe;
end $$;

-- 1 bis. normaliser_telephone : séparateurs explicites -------------------
-- Même règles qu'en phase 1, mais la liste des séparateurs ne dépend plus
-- de la langue du serveur et couvre les caractères produits par les
-- carnets de contacts (espace fine insécable, tirets typographiques).
-- Identique à lib/utils/telephone.dart.

create or replace function public.normaliser_telephone(p text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  s text;
  d text;
begin
  if p is null then
    return null;
  end if;
  -- Séparateurs explicites (pas de classe dépendant de la langue du
  -- serveur) : espace, tabulations/retours, espaces insécables (fine et
  -- normale), espace chiffre, espace fine, . ( ) / et tirets.
  s := regexp_replace(p,
    '[ ' || chr(9) || chr(10) || chr(11) || chr(12) || chr(13) || chr(160) || chr(8199)
    || chr(8201) || chr(8239) || '.()/' || chr(8208) || chr(8209) || chr(8210) || chr(8211) || '-]',
    '', 'g');

  if s ~ '^\+' then
    d := substr(s, 2);
  elsif s ~ '^00' then
    d := substr(s, 3);
  elsif s ~ '^0[0-9]{9}$' then
    d := '33' || substr(s, 2);
  else
    return null;
  end if;

  if d !~ '^[0-9]+$' then
    return null;
  end if;

  if d ~ '^(33|262|590|594|596)0[0-9]{9}$' then
    d := substr(d, 1, length(d) - 10) || substr(d, length(d) - 8);
  end if;

  if d ~ '^33(639|69[23])[0-9]{6}$' then
    d := '262' || substr(d, 3);
  elsif d ~ '^3369[01][0-9]{6}$' then
    d := '590' || substr(d, 3);
  elsif d ~ '^33694[0-9]{6}$' then
    d := '594' || substr(d, 3);
  elsif d ~ '^3369[67][0-9]{6}$' then
    d := '596' || substr(d, 3);
  end if;

  if d ~ '^33' then
    return case when d ~ '^33[67][0-9]{8}$' then '+' || d end;
  elsif d ~ '^262' then
    return case when d ~ '^262(639|69[23])[0-9]{6}$' then '+' || d end;
  elsif d ~ '^590' then
    return case when d ~ '^59069[01][0-9]{6}$' then '+' || d end;
  elsif d ~ '^594' then
    return case when d ~ '^594694[0-9]{6}$' then '+' || d end;
  elsif d ~ '^596' then
    return case when d ~ '^59669[67][0-9]{6}$' then '+' || d end;
  end if;

  return case when d ~ '^[1-9][0-9]{7,14}$' then '+' || d end;
end;
$$;

-- Vecteurs de test : la migration s'arrête ici si un seul est faux.
do $$
declare
  v record;
  n int := 0;
begin
  for v in
    select * from (values
      ('06 00 00 12 34', '+33600001234'),
      ('0600001234', '+33600001234'),
      ('+33 6 00 00 12 34', '+33600001234'),
      ('+33600001234', '+33600001234'),
      ('0033 6 00 00 12 34', '+33600001234'),
      ('+33 (0)6 00 00 12 34', '+33600001234'),
      ('06.00.00.12.34', '+33600001234'),
      ('06-00-00-12-34', '+33600001234'),
      ('06' || chr(160) || '00' || chr(160) || '00 12 34', '+33600001234'),
      ('  06 00 00 12 34  ', '+33600001234'),
      ('+33' || chr(8239) || '6' || chr(8239) || '00' || chr(8239) || '00 12 34', '+33600001234'),
      ('06' || chr(8209) || '00' || chr(8211) || '00 12 34', '+33600001234'),
      ('06' || chr(9) || '00 00 12 34', '+33600001234'),
      ('07 81 22 33 44', '+33781223344'),
      ('0692 12 34 56', '+262692123456'),
      ('+262 692 12 34 56', '+262692123456'),
      ('+33 692 12 34 56', '+262692123456'),
      ('+262 (0)692 12 34 56', '+262692123456'),
      ('0693 12 34 56', '+262693123456'),
      ('0639 12 34 56', '+262639123456'),
      ('0690 12 34 56', '+590690123456'),
      ('0691 12 34 56', '+590691123456'),
      ('0694 12 34 56', '+594694123456'),
      ('0696 12 34 56', '+596696123456'),
      ('0697 12 34 56', '+596697123456'),
      ('+44 7911 123456', '+447911123456'),
      ('0044 7911 123456', '+447911123456'),
      ('+1 202 555 0143', '+12025550143'),
      ('0000', null),
      ('00', null),
      ('t', null),
      ('', null),
      ('01 23 45 67 89', null),
      ('+33 1 23 45 67 89', null),
      ('09 70 00 00 00', null),
      ('6 00 00 12 34', null),
      ('07911 123456', null),
      ('+33 12345', null),
      ('+262 262 12 34 56', null),
      ('0692 12 34', null),
      ('06 00 00 12 34 8', null),
      ('+33 6 70 41 92 7a', null)
    ) as t(saisie, attendu)
  loop
    if normaliser_telephone(v.saisie) is distinct from v.attendu then
      raise exception 'normaliser_telephone(%) = %, attendu %',
        v.saisie, normaliser_telephone(v.saisie), v.attendu;
    end if;
    n := n + 1;
  end loop;
  if normaliser_telephone(null) is not null then
    raise exception 'normaliser_telephone(null) doit renvoyer null';
  end if;
  raise notice 'normaliser_telephone : % vecteurs OK', n;
end $$;

-- Recalcule uniquement les lignes dont la forme canonique changerait avec
-- cette version (aucune sur les données actuelles). La saisie d'origine
-- n'est pas modifiée : seule la colonne générée est recalculée.
do $$
declare
  n1 int; n2 int; n3 int;
begin
  update public.profiles set telephone = telephone
    where telephone_e164 is distinct from public.normaliser_telephone(telephone);
  get diagnostics n1 = row_count;
  update public.remplacants set telephone = telephone
    where telephone_e164 is distinct from public.normaliser_telephone(telephone);
  get diagnostics n2 = row_count;
  update public.pactes set destinataire_telephone = destinataire_telephone
    where destinataire_telephone_e164 is distinct from public.normaliser_telephone(destinataire_telephone);
  get diagnostics n3 = row_count;
  raise notice 'Formes canoniques recalculées : % compte(s), % fiche(s), % Swend(s).', n1, n2, n3;
end $$;

-- 2. Arrêt net si des doublons empêchent l'unicité (rien n'est corrigé ici)

do $$
declare
  n int;
begin
  select count(*) into n from (
    select telephone_e164 from public.profiles where telephone_e164 is not null
    group by telephone_e164 having count(*) > 1) x;
  if n > 0 then
    raise exception '% numéro(s) partagé(s) par plusieurs comptes : à résoudre avant cette phase (voir le diagnostic de la phase 1, section C).', n;
  end if;
  select count(*) into n from (
    select 1 from public.remplacants where telephone_e164 is not null
    group by pacte_id, cote, telephone_e164 having count(*) > 1) x;
  if n > 0 then
    raise exception '% personne(s) en double du même côté d''un Swend : à résoudre avant cette phase (diagnostic, section D).', n;
  end if;
end $$;

-- 3. Unicité canonique ----------------------------------------------------

create unique index if not exists profiles_telephone_e164_unique
  on public.profiles (telephone_e164) where telephone_e164 is not null;
drop index if exists public.profiles_telephone_unique;

create unique index if not exists remplacants_personne_unique_par_cote
  on public.remplacants (pacte_id, cote, telephone_e164) where telephone_e164 is not null;

-- 4. Numéro valide obligatoire pour toute nouvelle ligne ------------------
-- NOT VALID : s'applique aux nouvelles lignes ; validé ensuite si
-- l'existant le permet (sinon simple avertissement, rien n'est modifié).

do $$
declare
  c record;
begin
  for c in select * from (values
      ('profiles', 'profiles_telephone_valide', 'telephone_e164 is not null'),
      ('remplacants', 'remplacants_telephone_valide', 'telephone_e164 is not null'),
      ('pactes', 'pactes_destinataire_telephone_valide', 'destinataire_telephone_e164 is not null')
    ) as t(tab, nom, expr)
  loop
    if not exists (select 1 from pg_constraint where conname = c.nom) then
      execute format('alter table public.%I add constraint %I check (%s) not valid', c.tab, c.nom, c.expr);
    end if;
    begin
      execute format('alter table public.%I validate constraint %I', c.tab, c.nom);
    exception when check_violation then
      raise notice 'Contrainte % laissée non validée : des lignes existantes ont un numéro invalide (elles ne sont pas modifiées).', c.nom;
    end;
  end loop;
end $$;

-- 5. Comptes : numéro valide, figé, rattachement canonique à l'inscription

-- Numéro valide obligatoire ; figé une fois le compte créé (seule une
-- intervention manuelle depuis le SQL Editor peut le changer).
create or replace function public.verifier_telephone_profil()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.telephone is distinct from old.telephone
     and current_user in ('authenticated', 'anon') then
    raise exception 'telephone_fige';
  end if;
  if public.normaliser_telephone(new.telephone) is null then
    raise exception 'telephone_invalide';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_verifier_telephone_profil on public.profiles;
create trigger trg_verifier_telephone_profil
  before insert or update of telephone on public.profiles
  for each row execute function public.verifier_telephone_profil();

-- À la création d'un compte (le profil est inséré par handle_new_user,
-- inchangée) : rattache par numéro canonique les Swends et fiches qui
-- attendaient ce numéro, uniquement là où le lien est vide, et jamais une
-- fiche "personne de confiance" d'un Swend dont ce compte est participant.
create or replace function public.rattacher_nouveau_profil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.telephone_e164 is null then
    return new;
  end if;

  update pactes
    set destinataire_id = new.id
    where destinataire_id is null
      and destinataire_telephone_e164 = new.telephone_e164
      and initiateur_id is distinct from new.id;

  update remplacants r
    set profil_id = new.id
    where r.profil_id is null
      and r.telephone_e164 = new.telephone_e164
      and not exists (
        select 1 from pactes k
        where k.id = r.pacte_id
          and (k.initiateur_id = new.id or k.destinataire_id = new.id));

  return new;
end;
$$;

drop trigger if exists trg_rattacher_nouveau_profil on public.profiles;
create trigger trg_rattacher_nouveau_profil
  after insert on public.profiles
  for each row execute function public.rattacher_nouveau_profil();

-- 6. Swends : destinataire calculé par la base, jamais repris du client ----

create or replace function public.normaliser_nouveau_pacte()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e164 text := public.normaliser_telephone(new.destinataire_telephone);
begin
  if v_e164 is null then
    raise exception 'telephone_invalide';
  end if;
  new.destinataire_id := (select id from profiles where telephone_e164 = v_e164);
  if new.destinataire_id is not null and new.destinataire_id = new.initiateur_id then
    raise exception 'destinataire_est_initiateur';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_normaliser_nouveau_pacte on public.pactes;
create trigger trg_normaliser_nouveau_pacte
  before insert on public.pactes
  for each row execute function public.normaliser_nouveau_pacte();

-- L'app ne peut plus changer qui sont les participants d'un Swend.
create or replace function public.proteger_participants_pacte()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon')
     and (new.initiateur_id is distinct from old.initiateur_id
       or new.destinataire_id is distinct from old.destinataire_id
       or new.destinataire_telephone is distinct from old.destinataire_telephone) then
    raise exception 'modification_interdite';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_participants_pacte on public.pactes;
create trigger trg_proteger_participants_pacte
  before update on public.pactes
  for each row execute function public.proteger_participants_pacte();

-- 7. Personnes de confiance : numéro valide, lien canonique, garde-fous --
-- Remplace la version de un_imprevu_v2.sql (même nom, même trigger).

create or replace function public.normaliser_nouveau_remplacant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e164 text := public.normaliser_telephone(new.telephone);
  v_pacte pactes%rowtype;
begin
  select * into v_pacte from pactes where id = new.pacte_id for update;

  new.selectionne := false;
  new.demande_statut := null;

  if v_e164 is null then
    raise exception 'telephone_invalide';
  end if;

  new.profil_id := (select id from profiles where telephone_e164 = v_e164);

  if new.profil_id is not null
       and (new.profil_id = v_pacte.initiateur_id or new.profil_id = v_pacte.destinataire_id)
     or v_e164 = v_pacte.destinataire_telephone_e164
     or v_e164 = (select telephone_e164 from profiles where id = v_pacte.initiateur_id) then
    raise exception 'personne_est_participant';
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = new.pacte_id and cote = new.cote and telephone_e164 = v_e164
  ) then
    raise exception 'personne_deja_prevue';
  end if;

  if new.profil_id is not null and exists (
    select 1 from remplacants
    where pacte_id = new.pacte_id and cote <> new.cote
      and profil_id = new.profil_id and selectionne = true
  ) then
    new.demande_statut := 'cloturee';
  end if;

  return new;
end;
$$;

-- Plus aucune recherche de compte par numéro depuis l'app (pas
-- d'indicateur "Déjà sur Swend") ; la fonction reste utilisable côté
-- serveur, en forme canonique.
create or replace function public.trouver_profil_par_telephone(p_telephone text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from profiles
  where telephone_e164 = public.normaliser_telephone(p_telephone)
$$;

revoke execute on function public.trouver_profil_par_telephone(text) from public, anon, authenticated;

-- 8. Rattrapage des liens manqués (uniquement les liens vides) ------------

do $$
declare
  n_pactes int;
  n_fiches int;
begin
  update pactes k
    set destinataire_id = p.id
    from profiles p
    where k.destinataire_id is null
      and p.telephone_e164 = k.destinataire_telephone_e164
      and p.id is distinct from k.initiateur_id;
  get diagnostics n_pactes = row_count;

  update remplacants r
    set profil_id = p.id
    from profiles p, pactes k
    where r.profil_id is null
      and p.telephone_e164 = r.telephone_e164
      and k.id = r.pacte_id
      and p.id is distinct from k.initiateur_id
      and p.id is distinct from k.destinataire_id;
  get diagnostics n_fiches = row_count;

  raise notice 'Rattrapage : % Swend(s) et % fiche(s) rattachés à un compte existant.', n_pactes, n_fiches;
end $$;

-- 9. Vérification finale (résultat affiché) --------------------------------

select 'Index unique canonique des comptes' as verification,
  (to_regclass('public.profiles_telephone_e164_unique') is not null)::text as resultat
union all
select 'Ancien index sur la chaîne brute supprimé',
  (to_regclass('public.profiles_telephone_unique') is null)::text
union all
select 'Une personne par côté (index)',
  (to_regclass('public.remplacants_personne_unique_par_cote') is not null)::text
union all
select 'Recherche par numéro inaccessible à l''app',
  (not has_function_privilege('authenticated', 'public.trouver_profil_par_telephone(text)', 'execute'))::text
union all
select 'Triggers en place',
  (select count(*)::text || ' / 5' from pg_trigger
   where tgname in ('trg_verifier_telephone_profil', 'trg_rattacher_nouveau_profil',
     'trg_normaliser_nouveau_pacte', 'trg_proteger_participants_pacte',
     'trg_normaliser_nouveau_remplacant') and not tgisinternal)
union all
select 'Contraintes "numéro valide" validées',
  (select count(*)::text || ' / 3' from pg_constraint
   where conname in ('profiles_telephone_valide', 'remplacants_telephone_valide',
     'pactes_destinataire_telephone_valide') and convalidated)
union all
select 'Comptes au numéro valide',
  (select count(telephone_e164)::text || ' / ' || count(*)::text from public.profiles);
