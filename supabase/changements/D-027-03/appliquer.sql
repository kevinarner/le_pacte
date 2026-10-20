-- D-027-03 — échéance H-3 ferme (D-027, décision d'Eliot du 20/10/2026).
-- Une seule transaction : préconditions, migration
-- supabase/migrations/20261020000000_echeance_h3.sql (copie exacte),
-- planification du job swend-echeance-h3 (chaque minute), assertions. Toute
-- assertion fausse annule tout. Aucune donnée existante modifiée ; job
-- swend-rappels inchangé (toutes les 5 minutes).
begin;

-- 0. Préconditions --------------------------------------------------------------
do $$
begin
  -- Ordre des migrations : D-027-02 appliqué (annulation unique, motif
  -- echeance_h3 admis), D-027-03 pas encore.
  if to_regclass('public.fils_imprevu_fermes') is null
     or not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'appliquer_annulation')
     or pg_get_constraintdef((select oid from pg_constraint where conname = 'pactes_annule_motif_valeurs'
                              and conrelid = 'public.pactes'::regclass)) not ilike '%echeance_h3%' then
    raise exception 'D-027-03 : D-027-02 pas encore appliqué (ordre des migrations)';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
             and proname in ('echeance_h3_atteinte', 'appliquer_echeances_h3')) then
    raise exception 'D-027-03 : déjà appliqué (en tout ou partie)';
  end if;
  -- Les 7 fonctions remplacées sont exactement celles relues en production
  -- le 20/10/2026 (corps normalisé), une seule par nom.
  if (select count(*) from (values
    ('ajouter_et_demander_remplacement', 'd1e31b1225cbc29dbde728653e46d426'),
    ('annuler_demande_remplacement', '0b313996d6679b5eb80a21347ef49978'),
    ('envoyer_demandes_remplacement', '2b2bb34414a655a6ffc3dd07ce3ca726'),
    ('envoyer_rappels_dus', 'fa9ffe2576c7950f8555660332b95ced'),
    ('je_peux_finalement_venir', '9631961e9c168952cbc9e0c25584463f'),
    ('repondre_demande_remplacement', '902fd1203365bfbe2e234d5152610b44'),
    ('se_desister_du_remplacement', 'ce38814eb3f7e8b883fcfe0cced2dd78')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 7
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('ajouter_et_demander_remplacement', 'annuler_demande_remplacement', 'envoyer_demandes_remplacement', 'envoyer_rappels_dus', 'je_peux_finalement_venir', 'repondre_demande_remplacement', 'se_desister_du_remplacement')) <> 7 then
    raise exception 'D-027-03 : les fonctions à remplacer diffèrent de celles relues (paquet à refaire)';
  end if;
  -- Le moteur des rappels (qui appliquera aussi l'échéance) : job actif,
  -- toutes les 5 minutes, inchangé. Le job de l'échéance n'existe pas encore.
  if (select count(*) from cron.job where jobname = 'swend-rappels' and active
      and schedule = '*/5 * * * *' and command = 'select public.envoyer_rappels_dus()') <> 1 then
    raise exception 'D-027-03 : job swend-rappels différent de celui relu (paquet à refaire)';
  end if;
  if exists (select 1 from cron.job where jobname = 'swend-echeance-h3')
     or to_regprocedure('cron.schedule(text, text, text)') is null then
    raise exception 'D-027-03 : job swend-echeance-h3 déjà présent, ou pg_cron indisponible';
  end if;
  -- Aucun Swend en imprévu à moins de 3 heures de son heure : sinon le
  -- premier passage du moteur l'annulerait aussitôt (arbitrage nécessaire).
  if exists (select 1 from public.pactes p
             where p.statut = 'confirme' and p.date_retenue > now()
               and p.date_retenue <= now() + interval '3 hours 10 minutes'
               and exists (select 1 from public.imprevus_declares d where d.pacte_id = p.id)) then
    raise exception 'D-027-03 : un Swend en imprévu est déjà à moins de 3 heures (arbitrage nécessaire)';
  end if;
  -- Sauvegarde faite (étape « sauvegarde » de ce paquet).
  if to_regclass('sauvegarde.d027_03_fonctions_20261020') is null
     or to_regclass('sauvegarde.d027_03_pactes_20261020') is null then
    raise exception 'D-027-03 : sauvegarde absente';
  end if;
end $$;

-- ================================================================================
-- Migration 20261020000000_echeance_h3.sql (copie exacte)
-- ================================================================================

-- Migration : D-027, échéance H-3 ferme (décision d'Eliot du 20/10/2026).
-- À exécuter après annulation_et_conversations.sql. Sûre à ré-exécuter.
--
-- H-3 (3 heures avant l'heure du Swend, comme le rappel du Jour J) devient
-- la limite ferme pour résoudre un imprévu ; la recherche jusqu'à H est
-- abandonnée :
--  1. dès H-3 inclus, la base refuse toute recherche et toute réponse
--     (`echeance_h3`) : envoyer une demande, ajouter une personne et lui
--     demander, annuler une demande (ancienne app), « Je peux finalement
--     venir », accepter ou refuser une demande. Blocage strict : l'heure est
--     lue (clock_timestamp) une fois les verrous obtenus, au moment où
--     l'action serait validée, indépendamment de tout job ;
--  2. dès H-3 inclus, le désistement du remplaçant sélectionné annule le
--     Swend immédiatement (motif `echeance_h3`), sans réactiver aucune
--     demande ;
--  3. à H-3, toute recherche non résolue (côté en imprévu sans remplaçant
--     sélectionné) annule le Swend (motif `echeance_h3`) :
--     appliquer_echeances_h3(), exécutée chaque minute par le job
--     `swend-echeance-h3` (créé par le paquet D-027-03, pas par cette
--     migration : pg_cron n'existe pas sur le banc) et en tête du moteur des
--     rappels (job `swend-rappels`, toutes les 5 minutes, fréquence
--     inchangée) — avant tout rappel du Jour J, si bien qu'un Swend annulé à
--     H-3 ne reçoit aucun rappel. Les deux appels ne peuvent pas annuler
--     deux fois (verrou du Swend, état relu) ;
--  4. un nouvel imprévu d'un titulaire dès H-3 passe par `annuler_swend()`
--     (inchangée : motif `titulaire`) ; l'app ne propose plus de recherche.
-- Un Swend dont les participants attendus restent disponibles est maintenu.
-- Annulation, notifications d'annulation, chat d'annulation et
-- conversations conservées : appliquer_annulation() (lot 2), inchangée.
-- Aucune donnée existante modifiée ; aucune notification au restaurant.

-- 1. Échéance ----------------------------------------------------------------------
create or replace function public.echeance_h3_atteinte(
  p_date_retenue timestamptz, p_maintenant timestamptz default now())
returns boolean
language sql
stable
set search_path = public
as $$
  select p_date_retenue is not null
     and p_maintenant >= echeance_rappel(p_date_retenue, 'j0')
$$;
revoke execute on function public.echeance_h3_atteinte(timestamptz, timestamptz) from public, anon, authenticated;

-- 2. Recherche et réponses : refusées dès H-3 ---------------------------------------
create or replace function public.envoyer_demandes_remplacement(p_remplacant_ids uuid[])
returns table (remplacant_id uuid, canal text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ids uuid[];
  v_pacte uuid;
  v_cote text;
  v_statut text;
  v_date timestamptz;
  v_titulaire_nom text;
  v_fiche remplacants%rowtype;
begin
  select coalesce(array_agg(distinct i), '{}') into v_ids
  from unnest(coalesce(p_remplacant_ids, '{}')) i where i is not null;
  if cardinality(v_ids) = 0 then
    raise exception 'aucune_personne';
  end if;

  -- Toutes les fiches existent, du même Swend et du même côté.
  select min(r.pacte_id::text)::uuid, min(r.cote)
    into v_pacte, v_cote
  from remplacants r where r.id = any (v_ids);
  if v_pacte is null
     or (select count(*) from remplacants r where r.id = any (v_ids)
           and r.pacte_id = v_pacte and r.cote = v_cote) <> cardinality(v_ids) then
    raise exception 'Non autorisé';
  end if;

  select statut, date_retenue,
         case when v_cote = 'initiateur' then initiateur_nom else destinataire_nom end
    into v_statut, v_date, v_titulaire_nom
  from pactes
  where id = v_pacte
    and ((v_cote = 'initiateur' and initiateur_id = v_uid)
      or (v_cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;
  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = v_pacte for update;
  -- D-027 (20/10) : dès H-3, plus aucune recherche ni réponse. Heure lue
  -- une fois les verrous obtenus (clock_timestamp) : une requête partie
  -- avant H-3 mais validée après n'aboutit pas.
  if echeance_h3_atteinte(v_date, clock_timestamp()) then
    raise exception 'echeance_h3';
  end if;

  if exists (select 1 from remplacants r where r.id = any (v_ids) and r.retire_le is not null) then
    raise exception 'demande_non_active';
  end if;
  if exists (select 1 from remplacants
             where pacte_id = v_pacte and cote = v_cote and selectionne = true) then
    raise exception 'place_deja_prise';
  end if;

  for v_fiche in
    select * from remplacants r where r.id = any (v_ids) order by r.id
  loop
    if v_fiche.selectionne or v_fiche.demande_statut is not null
       or v_fiche.indisponible_spontanement then
      raise exception 'personne_indisponible';
    end if;
    if v_fiche.profil_id is not null and exists (
      select 1 from remplacants o
      where o.pacte_id = v_pacte and o.cote <> v_cote
        and o.profil_id = v_fiche.profil_id and o.selectionne = true
    ) then
      raise exception 'personne_indisponible';
    end if;
  end loop;

  update remplacants r set demande_statut = 'envoyee' where r.id = any (v_ids);

  for v_fiche in
    select * from remplacants r where r.id = any (v_ids) order by r.id
  loop
    perform pousser_personne(v_fiche.id, 'On a besoin de toi',
      coalesce(v_titulaire_nom, 'Quelqu''un') || ' te demande de prendre sa place pour un Swend.');
    remplacant_id := v_fiche.id;
    canal := case when v_fiche.profil_id is not null then 'notification' else 'message' end;
    return next;
  end loop;
end;
$$;

create or replace function public.ajouter_et_demander_remplacement(
  p_pacte_id uuid,
  p_cote text,
  p_prenom text,
  p_nom text,
  p_telephone text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_statut text;
  v_date timestamptz;
  v_titulaire_nom text;
  v_id uuid;
  v_demande text;
begin
  if coalesce(trim(p_prenom), '') = '' or coalesce(trim(p_nom), '') = ''
     or coalesce(trim(p_telephone), '') = '' then
    raise exception 'champs_manquants';
  end if;

  select statut, date_retenue,
         case when p_cote = 'initiateur' then initiateur_nom else destinataire_nom end
    into v_statut, v_date, v_titulaire_nom
  from pactes
  where id = p_pacte_id
    and ((p_cote = 'initiateur' and initiateur_id = v_uid)
      or (p_cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;
  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = p_pacte_id for update;
  -- D-027 (20/10) : dès H-3, plus aucune recherche ni réponse. Heure lue
  -- une fois les verrous obtenus (clock_timestamp) : une requête partie
  -- avant H-3 mais validée après n'aboutit pas.
  if echeance_h3_atteinte(v_date, clock_timestamp()) then
    raise exception 'echeance_h3';
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = p_pacte_id and cote = p_cote and selectionne = true
  ) then
    raise exception 'place_deja_prise';
  end if;

  insert into remplacants (pacte_id, cote, prenom, nom, telephone, email)
  values (p_pacte_id, p_cote, trim(p_prenom), trim(p_nom), trim(p_telephone), '')
  returning id, demande_statut into v_id, v_demande;

  if v_demande is not null then
    raise exception 'personne_indisponible';
  end if;

  update remplacants set demande_statut = 'envoyee' where id = v_id;
  perform pousser_personne(v_id, 'On a besoin de toi',
    coalesce(v_titulaire_nom, 'Quelqu''un') || ' te demande de prendre sa place pour un Swend.');
  return v_id;
end;
$$;

create or replace function public.annuler_demande_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_date timestamptz;
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select date_retenue into v_date from pactes
  where id = v_fiche.pacte_id
    and ((v_fiche.cote = 'initiateur' and initiateur_id = v_uid)
      or (v_fiche.cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  -- D-027 (20/10) : dès H-3, plus aucune recherche ni réponse. Heure lue
  -- une fois les verrous obtenus (clock_timestamp) : une requête partie
  -- avant H-3 mais validée après n'aboutit pas.
  if echeance_h3_atteinte(v_date, clock_timestamp()) then
    raise exception 'echeance_h3';
  end if;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_fiche.selectionne or v_fiche.demande_statut = 'acceptee' then
    raise exception 'deja_acceptee';
  end if;
  if v_fiche.demande_statut is distinct from 'envoyee' then
    raise exception 'demande_non_active';
  end if;

  update remplacants set demande_statut = null where id = p_remplacant_id;

  if not exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote and retire_le is null
      and (selectionne or demande_statut in ('envoyee', 'refusee', 'desistee'))
  ) then
    delete from imprevus_declares where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote;
  end if;

  perform pousser_personne(p_remplacant_id, 'Swend',
    prenom_titulaire_de(p_remplacant_id) || ' a annulé sa demande.');
end;
$$;

create or replace function public.je_peux_finalement_venir(p_pacte_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_cote text;
  v_statut text;
  v_date timestamptz;
  v_prenom text;
  v_closes uuid[];
  v_id uuid;
begin
  select case when initiateur_id = v_uid then 'initiateur'
              when destinataire_id = v_uid then 'destinataire' end,
         statut, date_retenue,
         coalesce(nullif(split_part(trim(case when initiateur_id = v_uid then initiateur_nom
                                              else destinataire_nom end), ' ', 1), ''), 'Ton contact')
    into v_cote, v_statut, v_date, v_prenom
  from pactes
  where id = p_pacte_id and v_uid is not null
    and (initiateur_id = v_uid or destinataire_id = v_uid)
  for update;
  if v_cote is null then
    raise exception 'Non autorisé';
  end if;
  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = p_pacte_id for update;
  -- D-027 (20/10) : dès H-3, plus aucune recherche ni réponse. Heure lue
  -- une fois les verrous obtenus (clock_timestamp) : une requête partie
  -- avant H-3 mais validée après n'aboutit pas.
  if echeance_h3_atteinte(v_date, clock_timestamp()) then
    raise exception 'echeance_h3';
  end if;

  if exists (select 1 from remplacants
             where pacte_id = p_pacte_id and cote = v_cote and selectionne = true) then
    raise exception 'place_deja_prise';
  end if;
  if not exists (select 1 from imprevus_declares
                 where pacte_id = p_pacte_id and cote = v_cote) then
    raise exception 'aucun_imprevu';
  end if;

  perform set_config('swend.retour_en_cours', 'on', true);
  with c as (
    update remplacants set demande_statut = null
    where pacte_id = p_pacte_id and cote = v_cote and demande_statut = 'envoyee'
    returning id
  )
  select coalesce(array_agg(id order by id), '{}') into v_closes from c;
  perform set_config('swend.retour_en_cours', 'off', true);

  delete from imprevus_declares where pacte_id = p_pacte_id and cote = v_cote;

  foreach v_id in array v_closes loop
    perform pousser_personne(v_id, 'Plus besoin de répondre',
      v_prenom || ' pourra finalement être là pour ce Swend.');
  end loop;
end;
$$;

create or replace function public.repondre_demande_remplacement(
  p_remplacant_id uuid,
  p_accepte boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_date timestamptz;
  v_personne text;
  v_closes uuid[];
  v_id uuid;
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;
  -- D-027 (20/10) : dès H-3, plus aucune recherche ni réponse. Heure lue
  -- une fois les verrous obtenus (clock_timestamp) : une requête partie
  -- avant H-3 mais validée après n'aboutit pas.
  if echeance_h3_atteinte(v_date, clock_timestamp()) then
    raise exception 'echeance_h3';
  end if;

  if v_fiche.demande_statut is distinct from 'envoyee' then
    if v_fiche.demande_statut = 'cloturee' then
      raise exception 'place_deja_prise';
    end if;
    raise exception 'demande_non_active';
  end if;

  v_personne := coalesce(nullif(trim(v_fiche.prenom), ''), 'Une personne de confiance');

  if not p_accepte then
    update remplacants set demande_statut = 'refusee' where id = p_remplacant_id;
    if not exists (
      select 1 from remplacants
      where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote
        and (demande_statut = 'envoyee' or selectionne)
    ) then
      perform pousser_titulaire(p_remplacant_id, 'Personne n’est disponible pour l’instant',
        'Tu peux solliciter quelqu’un d’autre.', true);
    end if;
    return;
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote
      and profil_id = v_uid and selectionne = true
  ) then
    raise exception 'deja_remplacant_autre_cote';
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote and selectionne = true
  ) then
    raise exception 'place_deja_prise';
  end if;

  update remplacants
    set selectionne = true, demande_statut = 'acceptee'
    where id = p_remplacant_id;

  -- Même côté : demandes en attente closes par cette acceptation.
  with c as (
    update remplacants
      set demande_statut = 'cloturee'
      where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote
        and id <> p_remplacant_id
        and demande_statut = 'envoyee'
      returning id
  ), m as (
    insert into clotures_demandes (remplacant_id, motif, fiche_acceptee, statut_avant)
    select id, 'acceptation', p_remplacant_id, 'envoyee' from c
    on conflict (remplacant_id) do update
      set motif = excluded.motif, fiche_acceptee = excluded.fiche_acceptee,
          statut_avant = excluded.statut_avant, cloture_le = clock_timestamp()
    returning remplacant_id
  )
  select coalesce(array_agg(remplacant_id order by remplacant_id), '{}') into v_closes from m;

  -- Autre côté : la même personne n'y est plus disponible.
  with o as (
    select id, demande_statut from remplacants
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote
      and profil_id = v_uid and retire_le is null
      and (demande_statut is null or demande_statut = 'envoyee')
  ), c as (
    update remplacants r set demande_statut = 'cloturee'
    from o where r.id = o.id
    returning r.id, o.demande_statut as avant
  )
  insert into clotures_demandes (remplacant_id, motif, fiche_acceptee, statut_avant)
  select id, 'autre_cote', null, avant from c
  on conflict (remplacant_id) do update
    set motif = excluded.motif, fiche_acceptee = null,
        statut_avant = excluded.statut_avant, cloture_le = clock_timestamp();

  -- Push : le titulaire (sauf double remplacement, D-021 : sa propre push
  -- d'annulation suffit) et les personnes qui attendaient une réponse.
  if not exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote and selectionne = true
  ) then
    perform pousser_titulaire(p_remplacant_id, v_personne || ' a accepté',
      v_personne || ' sera là à ta place le jour J.');
  end if;
  foreach v_id in array v_closes loop
    perform pousser_personne(v_id, 'Plus besoin de répondre', 'La place a été prise pour ce Swend.');
  end loop;
end;
$$;

-- 3. Désistement dès H-3 : annulation immédiate --------------------------------------
create or replace function public.se_desister_du_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_date timestamptz;
  v_personne text;
  x record;
  v_cible text;
  v_reactivees uuid[] := '{}';
  v_meme_cote integer := 0;
  v_id uuid;
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;
  if not v_fiche.selectionne or v_fiche.demande_statut is distinct from 'acceptee' then
    raise exception 'demande_non_active';
  end if;

  v_personne := coalesce(nullif(trim(v_fiche.prenom), ''), 'Une personne de confiance');

  -- D-027 (20/10) : dès H-3, le désistement annule le Swend, sans réactiver
  -- aucune demande. Le titulaire de son côté est prévenu ; l'autre titulaire
  -- reçoit la push d'annulation habituelle (« X ne pourra finalement pas
  -- être là. »), sans rien apprendre du remplacement.
  if echeance_h3_atteinte(v_date, clock_timestamp()) then
    update remplacants
      set selectionne = false, demande_statut = 'desistee'
      where id = p_remplacant_id;
    perform pousser_titulaire(p_remplacant_id, 'Le Swend est annulé',
      v_personne || ' ne peut finalement plus venir.', true);
    perform appliquer_annulation(v_fiche.pacte_id, v_fiche.cote, 'echeance_h3', null);
    return;
  end if;

  update remplacants
    set selectionne = false, demande_statut = 'desistee'
    where id = p_remplacant_id;

  -- Toute fiche close de ce Swend dont la clôture peut maintenant être levée.
  for x in
    select r.id, r.cote, r.profil_id, c.motif, c.fiche_acceptee, c.statut_avant
    from remplacants r
    left join clotures_demandes c on c.remplacant_id = r.id
    where r.pacte_id = v_fiche.pacte_id
      and r.demande_statut = 'cloturee'
      and r.retire_le is null
      and (
        -- même côté : close par cette acceptation, ou par une sélection de
        -- l'autre côté (vérifiée plus bas), ou sans mémoire (ancien comportement)
        (r.cote = v_fiche.cote and (c.motif is null or c.motif = 'autre_cote'
                                    or c.fiche_acceptee = p_remplacant_id))
        -- autre côté : fiches de la personne qui se désiste
        or (r.cote <> v_fiche.cote and r.profil_id = v_uid)
      )
    order by r.id
  loop
    -- Son côté a pris quelqu'un : rien ne bouge.
    continue when exists (select 1 from remplacants o
                          where o.pacte_id = v_fiche.pacte_id and o.cote = x.cote and o.selectionne);
    -- La personne remplace toujours l'autre titulaire : elle reste indisponible
    -- de ce côté, en gardant ce qu'elle était (en attente) pour plus tard.
    if x.profil_id is not null and exists (
      select 1 from remplacants o
      where o.pacte_id = v_fiche.pacte_id and o.cote <> x.cote
        and o.profil_id = x.profil_id and o.selectionne
    ) then
      if x.motif = 'acceptation' then
        update clotures_demandes set motif = 'autre_cote', fiche_acceptee = null
        where remplacant_id = x.id;
      end if;
      continue;
    end if;

    v_cible := case when x.motif = 'acceptation' then 'envoyee'
                    when x.motif = 'autre_cote' then x.statut_avant
                    else null end;
    if v_cible = 'envoyee' and not exists (
      select 1 from imprevus_declares where pacte_id = v_fiche.pacte_id and cote = x.cote
    ) then
      v_cible := null;
    end if;

    update remplacants set demande_statut = v_cible,
      message_a_renvoyer = coalesce(v_cible = 'envoyee' and x.profil_id is null, false)
    where id = x.id;
    if v_cible = 'envoyee' then
      v_reactivees := v_reactivees || x.id;
      if x.cote = v_fiche.cote then
        v_meme_cote := v_meme_cote + 1;
      end if;
    end if;
  end loop;

  perform pousser_titulaire(p_remplacant_id, v_personne || ' ne peut finalement plus venir',
    case when v_meme_cote > 0
      then 'Les personnes qui n’avaient pas encore répondu peuvent à nouveau le faire.'
      else 'Tu peux solliciter quelqu’un d’autre.' end);
  foreach v_id in array v_reactivees loop
    perform pousser_personne(v_id, 'Ta réponse est finalement attendue',
      'La place est à nouveau disponible pour ce Swend.');
  end loop;
end;
$$;

-- 4. Recherche non résolue à H-3 : annulation -------------------------------------------
-- Appelée chaque minute (job swend-echeance-h3) et par le moteur des rappels.
-- Délai de traitement : au mieux la minute qui suit H-3 ; si un job échoue,
-- l'annulation attend l'exécution suivante réussie (aucune garantie de délai
-- sans job) ; les actions, elles, sont refusées dès H-3 quoi qu'il arrive.
-- Pour chaque Swend scellé dont H-3 est atteint (et H pas encore), dont au
-- moins un côté est en imprévu sans remplaçant sélectionné : annulation
-- (motif `echeance_h3`, sans auteur), mêmes verrous que les actions (le
-- Swend, puis ses fiches) ; l'état est relu sous verrou, si bien qu'une
-- acceptation validée juste avant maintient le Swend. Notifications :
--  * titulaire de chaque côté qui cherchait : « Le Swend est annulé /
--    Personne n’a pu prendre ta place à temps. » ;
--  * appliquer_annulation() : l'autre titulaire (un seul côté cherchait :
--    « X ne pourra finalement pas être là. »), remplaçant sélectionné de
--    l'autre côté, demandes encore en attente (« Tu n’as plus besoin de
--    répondre. ») ; refus, désistements, personnes seulement prévues : rien.
-- Idempotente (un Swend annulé n'est plus `confirme`). Renvoie le nombre de
-- Swends annulés.
create or replace function public.appliquer_echeances_h3(p_maintenant timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  p record;
  v_cotes text[];
  v_cote text;
  n integer := 0;
begin
  for v_id in
    select pa.id from pactes pa
    where pa.statut = 'confirme'
      and pa.date_retenue is not null
      and pa.date_retenue > p_maintenant
      and echeance_h3_atteinte(pa.date_retenue, p_maintenant)
      and exists (select 1 from imprevus_declares d where d.pacte_id = pa.id)
    order by pa.id
  loop
    select pa.id, pa.statut, pa.date_retenue, pa.initiateur_id, pa.destinataire_id
      into p
    from pactes pa where pa.id = v_id for update;
    perform 1 from remplacants where pacte_id = v_id for update;
    continue when p.statut <> 'confirme';

    select coalesce(array_agg(d.cote order by d.cote), '{}') into v_cotes
    from imprevus_declares d
    where d.pacte_id = v_id
      and not exists (select 1 from remplacants r
                      where r.pacte_id = v_id and r.cote = d.cote and r.selectionne);
    continue when cardinality(v_cotes) = 0;

    foreach v_cote in array v_cotes loop
      if (case when v_cote = 'initiateur' then p.initiateur_id else p.destinataire_id end) is not null then
        perform notifier(case when v_cote = 'initiateur' then p.initiateur_id else p.destinataire_id end,
          'Le Swend est annulé', 'Personne n’a pu prendre ta place à temps.',
          jsonb_build_object('type', 'pacte', 'pacte_id', v_id));
      end if;
    end loop;
    perform appliquer_annulation(v_id,
      case when cardinality(v_cotes) = 1 then v_cotes[1] end, 'echeance_h3', null);
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.appliquer_echeances_h3(timestamptz) from public, anon, authenticated;

-- 5. Rappels : l'échéance d'abord ------------------------------------------------------
-- Le moteur des rappels (job `swend-rappels`, toutes les 5 minutes) applique
-- l'échéance H-3 avant d'envoyer quoi que ce soit : un Swend annulé à H-3 ne
-- reçoit plus aucun rappel. Le reste est inchangé (rappels_jour_j.sql).
create or replace function public.envoyer_rappels_dus(p_maintenant timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fenetre constant interval := interval '30 minutes';
  p record;
  v_type text;
  v_echeance timestamptz;
  v_cote text;
  v_etat text;
  v_titulaire uuid;
  v_prenom_titulaire text;
  v_prenom_autre text;
  v_fiche record;
  n integer := 0;
begin
  perform appliquer_echeances_h3(p_maintenant);
  for p in
    select pa.id, pa.date_retenue, pa.scelle_le, pa.type, pa.initiateur_id, pa.destinataire_id,
           split_part(trim(pa.initiateur_nom), ' ', 1) as prenom_initiateur,
           split_part(trim(pa.destinataire_nom), ' ', 1) as prenom_destinataire,
           r.nom as restaurant
    from pactes pa left join restaurants r on r.id = pa.restaurant_id
    where pa.statut = 'confirme'
      and pa.scelle_le is not null
      and pa.date_retenue is not null
      and pa.date_retenue > p_maintenant
      and pa.date_retenue <= p_maintenant + interval '8 days'
  loop
    foreach v_type in array array['j7', 'j3', 'j1', 'j0'] loop
      v_echeance := echeance_rappel(p.date_retenue, v_type);
      continue when not (v_echeance <= p_maintenant
                         and p_maintenant < v_echeance + c_fenetre
                         and p.scelle_le <= v_echeance);
      -- Une échéance n'est traitée qu'une fois par Swend (même si le moteur
      -- tourne deux fois, ou en parallèle) : qui en fait partie est décidé ici.
      insert into rappels_echeances (pacte_id, type_rappel, echeance)
      values (p.id, v_type, v_echeance)
      on conflict do nothing;
      continue when not found;

      foreach v_cote in array array['initiateur', 'destinataire'] loop
        if v_cote = 'initiateur' then
          v_titulaire := p.initiateur_id; v_prenom_titulaire := p.prenom_initiateur; v_prenom_autre := p.prenom_destinataire;
        else
          v_titulaire := p.destinataire_id; v_prenom_titulaire := p.prenom_destinataire; v_prenom_autre := p.prenom_initiateur;
        end if;
        v_etat := etat_cote_titulaire(p.id, v_cote);
        if v_etat = 'remplace' then
          select r.profil_id, trim(r.prenom) as prenom into v_fiche
          from remplacants r where r.pacte_id = p.id and r.cote = v_cote and r.selectionne limit 1;
          -- Le titulaire remplacé : « Kevin prend ta place ».
          n := n + envoyer_rappel(p.id, v_titulaire, v_type, 'remplace', p.date_retenue, p.restaurant, p.type, v_fiche.prenom);
          -- La personne qui prend sa place : rappel « repas » avec l'autre titulaire.
          n := n + envoyer_rappel(p.id, v_fiche.profil_id, v_type, 'repas', p.date_retenue, p.restaurant, p.type, v_prenom_autre);
        elsif v_etat = 'cherche' then
          n := n + envoyer_rappel(p.id, v_titulaire, v_type, 'cherche', p.date_retenue, p.restaurant, p.type, v_prenom_autre);
        else
          n := n + envoyer_rappel(p.id, v_titulaire, v_type, 'repas', p.date_retenue, p.restaurant, p.type, v_prenom_autre);
        end if;
      end loop;
    end loop;
  end loop;
  return n;
end;
$$;
revoke execute on function public.envoyer_rappels_dus(timestamptz) from public, anon, authenticated;

-- ================================================================================
-- Planification : l'échéance chaque minute (job swend-echeance-h3). Fréquence
-- des rappels inchangée. Copie de supabase/planification/echeance_h3_pg_cron.sql.
-- ================================================================================
select cron.schedule('swend-echeance-h3', '* * * * *', 'select public.appliquer_echeances_h3()');

-- ================================================================================
-- Assertions
-- ================================================================================
do $$
begin
  -- Fonctions créées, non exécutables par l'app.
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
      and proname in ('echeance_h3_atteinte', 'appliquer_echeances_h3')) <> 2
     or has_function_privilege('authenticated', 'public.appliquer_echeances_h3(timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.appliquer_echeances_h3(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.echeance_h3_atteinte(timestamptz, timestamptz)', 'execute') then
    raise exception 'D-027-03 : fonctions de l''échéance absentes ou exposées';
  end if;
  -- Les 9 fonctions sont exactement celles testées (corps normalisé).
  if (select count(*) from (values
    ('ajouter_et_demander_remplacement', '41d62d5c89670158a44a3eb57fb146d4'),
    ('annuler_demande_remplacement', 'd4f041ba4caafe35ad85b31b1742f8df'),
    ('appliquer_echeances_h3', '82b7fc5ec4048a57e8bff07cc8667bbc'),
    ('echeance_h3_atteinte', '57ea12a3892a202ebec0b942113e0471'),
    ('envoyer_demandes_remplacement', '7bb8a3ad2d46036b260192354b3d6012'),
    ('envoyer_rappels_dus', 'e1ba350897cefd6b75f460fb87821481'),
    ('je_peux_finalement_venir', 'c1ae4f8bd5140f7eed108040376fc754'),
    ('repondre_demande_remplacement', '8f6e448b412d297ec245d74d53468ee7'),
    ('se_desister_du_remplacement', '5f64a11b94a473d7796f6240d14d89ca')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 9 then
    raise exception 'D-027-03 : une fonction n''est pas celle testée';
  end if;
  -- Droits des fonctions remplacées inchangés.
  if exists (select 1 from sauvegarde.d027_03_fonctions_20261020 s
             join pg_proc p on p.proname = s.nom and p.pronamespace = 'public'::regnamespace
             where (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a) is distinct from s.droits) then
    raise exception 'D-027-03 : droits d''une fonction remplacée modifiés';
  end if;
  -- Aucune donnée existante modifiée (aucune annulation par la migration).
  if exists (select 1 from sauvegarde.d027_03_pactes_20261020 s join public.pactes p on p.id = s.id
             where p.statut is distinct from s.statut or p.annule_le is distinct from s.annule_le
                or p.annule_motif is distinct from s.annule_motif or p.date_retenue is distinct from s.date_retenue) then
    raise exception 'D-027-03 : une donnée existante a changé';
  end if;
  -- Jobs : swend-rappels inchangé (toutes les 5 minutes) ; swend-echeance-h3
  -- créé, actif, chaque minute.
  if (select count(*) from cron.job where jobname = 'swend-rappels' and active
      and schedule = '*/5 * * * *' and command = 'select public.envoyer_rappels_dus()') <> 1 then
    raise exception 'D-027-03 : job swend-rappels modifié';
  end if;
  if (select count(*) from cron.job where jobname = 'swend-echeance-h3' and active
      and schedule = '* * * * *' and command = 'select public.appliquer_echeances_h3()') <> 1 then
    raise exception 'D-027-03 : job swend-echeance-h3 absent ou différent';
  end if;
end $$;

commit;
