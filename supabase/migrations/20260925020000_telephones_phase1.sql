-- Chantier téléphone — PHASE 1 (sûre) : sauvegarde, normalisation,
-- colonnes E.164, diagnostic. AUCUNE donnée existante n'est modifiée,
-- aucun lien n'est créé ni corrigé, aucune contrainte n'est ajoutée.
-- Sûre à ré-exécuter (la sauvegarde n'est prise qu'à la première
-- exécution).
--
-- À exécuter en une fois dans le SQL Editor de Supabase. Le résultat
-- affiché est le rapport de diagnostic (dernière requête) : c'est lui
-- qu'il faut relire avant la phase 2.

-- 1. Sauvegarde -----------------------------------------------------------
-- Schéma non exposé par l'API, inaccessible aux utilisateurs de l'app.

create schema if not exists sauvegarde;
revoke all on schema sauvegarde from public, anon, authenticated;

create table if not exists sauvegarde.telephones_profiles_20260925 as
  select id, telephone, now() as sauvegarde_le from public.profiles;
create table if not exists sauvegarde.telephones_remplacants_20260925 as
  select id, pacte_id, cote, telephone, profil_id, selectionne, demande_statut,
         now() as sauvegarde_le
  from public.remplacants;
create table if not exists sauvegarde.telephones_pactes_20260925 as
  select id, initiateur_id, destinataire_id, destinataire_telephone,
         now() as sauvegarde_le
  from public.pactes;

-- 2. Normalisation --------------------------------------------------------
-- Renvoie la forme E.164 d'un numéro de MOBILE, ou NULL s'il est
-- invalide, fixe, ou ambigu. Règles :
--  * séparateurs ignorés (espaces, espace insécable, . - ( ) /) ;
--  * "+" ou "00" = indicatif international ;
--  * sans indicatif : numéro national français à 10 chiffres (0 + 9) ;
--  * "(0)" après un indicatif français ou d'outre-mer est retiré ;
--  * mobiles d'outre-mer ramenés à leur vrai indicatif, qu'ils soient
--    saisis en national (0692…) ou avec +33 (+33 692…) :
--    0639/0692/0693 → +262, 0690/0691 → +590, 0694 → +594,
--    0696/0697 → +596 ;
--  * France métropolitaine : mobiles 06/07 uniquement ;
--  * autres pays : forme E.164 valide (8 à 15 chiffres) — le caractère
--    "mobile" n'y est pas vérifiable sans base de numérotation par pays.

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
      ('06 70 41 92 77', '+33670419277'),
      ('0670419277', '+33670419277'),
      ('+33 6 70 41 92 77', '+33670419277'),
      ('+33670419277', '+33670419277'),
      ('0033 6 70 41 92 77', '+33670419277'),
      ('+33 (0)6 70 41 92 77', '+33670419277'),
      ('06.70.41.92.77', '+33670419277'),
      ('06-70-41-92-77', '+33670419277'),
      ('06' || chr(160) || '70' || chr(160) || '41 92 77', '+33670419277'),
      ('  06 70 41 92 77  ', '+33670419277'),
      ('+33' || chr(8239) || '6' || chr(8239) || '70' || chr(8239) || '41 92 77', '+33670419277'),
      ('06' || chr(8209) || '70' || chr(8211) || '41 92 77', '+33670419277'),
      ('06' || chr(9) || '70 41 92 77', '+33670419277'),
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
      ('6 70 41 92 77', null),
      ('07911 123456', null),
      ('+33 12345', null),
      ('+262 262 12 34 56', null),
      ('0692 12 34', null),
      ('06 70 41 92 77 8', null),
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

-- 3. Colonnes E.164 (calculées par la base, jamais écrites par l'app) ------
-- Aucune donnée existante n'est modifiée. Pas encore d'index ni de
-- contrainte : ce sera la phase 2, après relecture du diagnostic.

alter table public.profiles
  add column if not exists telephone_e164 text
  generated always as (public.normaliser_telephone(telephone)) stored;
alter table public.remplacants
  add column if not exists telephone_e164 text
  generated always as (public.normaliser_telephone(telephone)) stored;
alter table public.pactes
  add column if not exists destinataire_telephone_e164 text
  generated always as (public.normaliser_telephone(destinataire_telephone)) stored;

-- 4. Diagnostic (lecture seule) --------------------------------------------
-- Les numéros valides sont masqués (seuls l'indicatif et les 3 derniers
-- chiffres restent visibles) ; les saisies invalides sont montrées telles
-- quelles pour pouvoir les identifier.

create or replace function pg_temp.masquer(e164 text) returns text
language sql immutable as $$
  select case when e164 is null then null
    else left(e164, case when e164 ~ '^\+(262|590|594|596)' then 4 else 3 end)
         || '•••' || right(e164, 3) end
$$;

create or replace function pg_temp.raison_invalide(t text) returns text
language sql immutable as $$
  select case
    when t is null or btrim(t) = '' then 'vide'
    when regexp_replace(t, '[^0-9]', '', 'g') ~ '^(0|330|33)?[1-59][0-9]{8}$' then 'fixe (non mobile)'
    else 'format invalide'
  end
$$;

with
p as (select * from public.profiles),
r as (select * from public.remplacants),
k as (select * from public.pactes),
rapport as (
  -- A. Vue d'ensemble
  select 'A. Vue d''ensemble' as section, 'profiles' as cle,
    format('%s au total, %s valides, %s invalides, %s vides, %s saisis dans un autre format que E.164',
      count(*), count(telephone_e164),
      count(*) filter (where telephone_e164 is null and coalesce(btrim(telephone), '') <> ''),
      count(*) filter (where coalesce(btrim(telephone), '') = ''),
      count(*) filter (where telephone_e164 is not null and telephone <> telephone_e164)) as detail
  from p
  union all
  select 'A. Vue d''ensemble', 'remplacants',
    format('%s au total, %s valides, %s invalides, %s liés à un compte, %s non liés',
      count(*), count(telephone_e164), count(*) filter (where telephone_e164 is null),
      count(profil_id), count(*) filter (where profil_id is null))
  from r
  union all
  select 'A. Vue d''ensemble', 'pactes (destinataire)',
    format('%s au total, %s numéros valides, %s invalides, %s destinataires liés',
      count(*), count(destinataire_telephone_e164),
      count(*) filter (where destinataire_telephone_e164 is null), count(destinataire_id))
  from k

  -- B. Numéros invalides
  union all
  select 'B. Profil au numéro invalide', p.id::text,
    format('%s %s — "%s" (%s)', p.prenom, p.nom, p.telephone, pg_temp.raison_invalide(p.telephone))
  from p where p.telephone_e164 is null and coalesce(btrim(p.telephone), '') <> ''
  union all
  select 'B. Fiche au numéro invalide', r.id::text,
    format('pacte %s, côté %s : %s %s — "%s" (%s)%s', r.pacte_id, r.cote, r.prenom, r.nom,
      r.telephone, pg_temp.raison_invalide(r.telephone),
      case when r.selectionne or r.demande_statut is not null
        then ' [demande : ' || coalesce(r.demande_statut, '') || case when r.selectionne then ', a pris la place' else '' end || ']'
        else '' end)
  from r where r.telephone_e164 is null
  union all
  select 'B. Pacte au numéro de destinataire invalide', k.id::text,
    format('%s — "%s" (%s), statut %s', k.destinataire_nom, k.destinataire_telephone,
      pg_temp.raison_invalide(k.destinataire_telephone), k.statut)
  from k where k.destinataire_telephone_e164 is null

  -- C. BLOQUANT pour l'unicité : plusieurs comptes pour un même numéro
  union all
  select 'C. BLOQUANT — même numéro sur plusieurs comptes', pg_temp.masquer(e164),
    string_agg(format('%s (%s %s, saisi "%s")', id, prenom, nom, telephone), ' | ' order by id)
  from (select id, prenom, nom, telephone, telephone_e164 as e164 from p where telephone_e164 is not null) x
  group by e164 having count(*) > 1

  -- D. Même personne deux fois du même côté d'un même Swend
  union all
  select 'D. Même personne deux fois du même côté', format('pacte %s, côté %s', pacte_id, cote),
    string_agg(format('%s (%s %s, "%s", demande %s%s)', id, prenom, nom, telephone,
      coalesce(demande_statut, 'aucune'), case when selectionne then ', a pris la place' else '' end),
      ' | ' order by id)
  from r where telephone_e164 is not null
  group by pacte_id, cote, telephone_e164 having count(*) > 1

  -- E. Liens manqués aujourd'hui, que la forme canonique permettrait
  union all
  select 'E. Fiche non liée alors qu''un compte correspond', r.id::text,
    format('pacte %s, côté %s : %s %s ("%s") ↔ compte %s (%s %s, "%s")%s', r.pacte_id, r.cote,
      r.prenom, r.nom, r.telephone, p.id, p.prenom, p.nom, p.telephone,
      case when p.id in (k.initiateur_id, k.destinataire_id)
        then ' — ATTENTION : ce compte est un participant de ce Swend' else '' end)
  from r
  join p on p.telephone_e164 = r.telephone_e164
  join k on k.id = r.pacte_id
  where r.profil_id is null
  union all
  select 'E. Pacte au destinataire non lié alors qu''un compte correspond', k.id::text,
    format('%s ("%s") ↔ compte %s (%s %s, "%s")%s', k.destinataire_nom, k.destinataire_telephone,
      p.id, p.prenom, p.nom, p.telephone,
      case when p.id = k.initiateur_id then ' — ATTENTION : c''est l''initiateur lui-même' else '' end)
  from k join p on p.telephone_e164 = k.destinataire_telephone_e164
  where k.destinataire_id is null

  -- F. Liens existants incohérents (le numéro de la fiche ne correspond
  --    pas, même en forme canonique, au numéro du compte lié)
  union all
  select 'F. Fiche liée à un compte au numéro différent', r.id::text,
    format('pacte %s, côté %s : %s %s ("%s") liée au compte %s (%s %s, "%s")', r.pacte_id, r.cote,
      r.prenom, r.nom, r.telephone, p.id, p.prenom, p.nom, p.telephone)
  from r join p on p.id = r.profil_id
  where r.telephone_e164 is distinct from p.telephone_e164
  union all
  select 'F. Pacte lié à un destinataire au numéro différent', k.id::text,
    format('%s ("%s") lié au compte %s (%s %s, "%s")', k.destinataire_nom, k.destinataire_telephone,
      p.id, p.prenom, p.nom, p.telephone)
  from k join p on p.id = k.destinataire_id
  where k.destinataire_telephone_e164 is distinct from p.telephone_e164

  -- G. Un participant du Swend enregistré comme remplaçant (interdit)
  union all
  select 'G. Participant du Swend enregistré comme remplaçant', r.id::text,
    format('pacte %s, côté %s : %s %s — %s', r.pacte_id, r.cote, r.prenom, r.nom,
      case
        when r.profil_id = k.initiateur_id or (r.telephone_e164 is not null and r.telephone_e164 = pi.telephone_e164) then 'c''est l''initiateur'
        else 'c''est le destinataire' end)
  from r
  join k on k.id = r.pacte_id
  left join p pi on pi.id = k.initiateur_id
  left join p pd on pd.id = k.destinataire_id
  where r.profil_id in (k.initiateur_id, k.destinataire_id)
     or (r.telephone_e164 is not null and r.telephone_e164 in (pi.telephone_e164, pd.telephone_e164, k.destinataire_telephone_e164))
  union all
  select 'G. Pacte dont le destinataire est l''initiateur', k.id::text,
    format('%s', k.destinataire_nom)
  from k left join p pi on pi.id = k.initiateur_id
  where k.destinataire_id = k.initiateur_id
     or (k.destinataire_telephone_e164 is not null and k.destinataire_telephone_e164 = pi.telephone_e164)

  -- H. Pour information (autorisé) : même personne prévue des deux côtés
  union all
  select 'H. Info — même personne prévue des deux côtés d''un Swend', a.pacte_id::text,
    format('%s %s (%s)', a.prenom, a.nom, pg_temp.masquer(a.telephone_e164))
  from r a join r b on b.pacte_id = a.pacte_id and b.cote <> a.cote and b.telephone_e164 = a.telephone_e164
  where a.cote = 'initiateur'
)
select section, cle, detail from rapport order by section, cle;
