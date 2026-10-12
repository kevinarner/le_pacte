-- D-027-01 — « En cas d'imprévu », lot 1 : états et actions (D-027). Une
-- seule transaction : préconditions, migration
-- supabase/migrations/20261012000000_imprevu_etats_et_actions.sql (copie
-- exacte), assertions. Toute assertion fausse annule tout. Aucune donnée
-- existante modifiée : seule la table interne des déclarations d'imprévu est
-- remplie (côtés qui cherchent déjà ou déjà remplacés).
begin;

-- 0. Préconditions --------------------------------------------------------------
do $$
begin
  -- Ordre des migrations testé : R2 (R2-01) et D-023c (D-023c-01) appliqués.
  if not exists (select 1 from pg_trigger where tgname = 'trg_verrou_zz_dates_swend'
                 and tgrelid = 'public.pactes'::regclass and tgenabled = 'O')
     or not exists (select 1 from pg_trigger where tgname = 'trg_verrou_un_swend_par_paire'
                    and tgrelid = 'public.pactes'::regclass and tgenabled = 'O') then
    raise exception 'D-027-01 : R2-01 ou D-023c-01 pas encore appliqué (ordre des migrations)';
  end if;
  if to_regclass('public.imprevus_declares') is not null
     or to_regclass('public.clotures_demandes') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public'
                and table_name = 'remplacants' and column_name = 'message_a_renvoyer')
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('envoyer_demandes_remplacement', 'je_peux_finalement_venir', 'marquer_message_renvoye', 'pousser_personne', 'pousser_titulaire', 'prenom_titulaire_de', 'suivre_demande_avant', 'suivre_demande_apres'))
     or exists (select 1 from pg_trigger where tgrelid = 'public.remplacants'::regclass
                and tgname in ('trg_suivre_demande_avant', 'trg_suivre_demande_apres')) then
    raise exception 'D-027-01 : déjà appliqué (en tout ou partie)';
  end if;
  -- Les 9 fonctions remplacées sont exactement celles des migrations testées
  -- (gel_a_h.sql, fil_evenements_et_lectures.sql ; corps normalisé).
  if (select count(*) from (values
    ('ajouter_et_demander_remplacement', 'f05127e4f5451b63c94e4c655fb47172'),
    ('annuler_demande_remplacement', 'a6437d253deb62b5bb661bbfd5bc448b'),
    ('envoyer_demande_remplacement', '1751db53c54569452626d4b3e7738935'),
    ('etat_cote_titulaire', '9192fd4441222ee8a7dc5daa036e90c5'),
    ('journaliser_demande_remplacement', '15532fb3de53cfd63cf19c2d3f7484f4'),
    ('normaliser_nouveau_remplacant', '7d96b877f09aed71baeba79fc1c86332'),
    ('notifier_demande_remplacement', 'c8ecfca89ae18029fcb4e319d519c1cc'),
    ('repondre_demande_remplacement', '17ba2628dbe9dc921eefe9df8ef30569'),
    ('se_desister_du_remplacement', 'd96df4cab29ac3db951fd42586dacb00')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 9
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('ajouter_et_demander_remplacement', 'annuler_demande_remplacement', 'envoyer_demande_remplacement', 'etat_cote_titulaire', 'journaliser_demande_remplacement', 'normaliser_nouveau_remplacant', 'notifier_demande_remplacement', 'repondre_demande_remplacement', 'se_desister_du_remplacement')) <> 9 then
    raise exception 'D-027-01 : les fonctions à remplacer diffèrent de celles testées (paquet à refaire)';
  end if;
  -- Sauvegarde faite (étape « sauvegarde » de ce paquet).
  if to_regclass('sauvegarde.d027_01_fonctions_20261012') is null
     or to_regclass('sauvegarde.d027_01_remplacants_20261012') is null then
    raise exception 'D-027-01 : sauvegarde absente';
  end if;
end $$;

-- Déclarations attendues après le remplissage (même règle que la migration).
create temp table d027_attendu on commit drop as
select distinct r.pacte_id, r.cote
from public.remplacants r join public.pactes p on p.id = r.pacte_id
where p.statut = 'confirme' and r.retire_le is null
  and (r.selectionne or r.demande_statut in ('envoyee', 'refusee', 'desistee', 'acceptee'));

-- ================================================================================
-- Migration 20261012000000_imprevu_etats_et_actions.sql (copie exacte)
-- ================================================================================

-- Migration : « En cas d'imprévu », lot 1 — états et actions (D-027).
-- À exécuter après nouveau_swend.sql. Sûre à ré-exécuter.
--
-- Contenu :
--  0. Déclaration d'imprévu par côté (table interne imprevus_declares) :
--     posée dès qu'une demande de ce côté existe, effacée par « Je peux
--     finalement venir » (ou par l'annulation de la dernière demande, tant
--     que l'ancienne action existe). Elle remplace le calcul de l'état
--     « cherche » d'après les fiches : après un retour, les refus restent
--     mais le titulaire n'est plus en imprévu. Prépare les échéances H-3 / H
--     (lot 4, non implémentées ici).
--  1. Clôtures à mémoire (table interne clotures_demandes) : une demande
--     clôturée par une acceptation se souvient de laquelle ; une fiche
--     clôturée parce que la même personne a pris la place de l'autre
--     titulaire se souvient de son état d'avant. Seules ces deux clôtures
--     sont réversibles (désistement).
--  2. Message à renvoyer (remplacants.message_a_renvoyer) : une demande
--     réactivée pour une personne sans compte (aucune push possible) ne
--     redevient pas active en silence ; le titulaire voit « Renvoyer le
--     message à … » jusqu'à ce qu'il l'ait relancé (marquer_message_renvoye).
--  3. Actions :
--     - envoyer_demandes_remplacement(ids[]) : envoi groupé, tout ou rien,
--       personnes avec et sans compte mélangées ; renvoie le canal de remise
--       de chaque demande (« notification » ou « message ») ;
--       envoyer_demande_remplacement(id) en devient le cas d'une personne ;
--     - je_peux_finalement_venir(pacte) : avant toute acceptation, les
--       demandes en attente sont closes, le côté redevient normal ;
--     - repondre_demande_remplacement : clôtures mémorisées ; le titulaire
--       n'est prévenu d'un refus que si plus aucune demande n'est en attente ;
--     - se_desister_du_remplacement : les demandes en attente avant cette
--       acceptation redeviennent actives (push, ou message à renvoyer) ;
--       les refus restent des refus.
--  4. Notifications envoyées par les fonctions elles-mêmes, textes D-027
--     (tutoiement). Le déclencheur notifier_demande_remplacement ne garde que
--     l'indisponibilité spontanée (D-008).
--  5. Fil : nouveaux événements « demande_reactivee » et « retour_titulaire ».
--
-- Hors lot 1 (inchangé ici) : annulation (annuler_swend, double
-- remplacement : lot 2), écran de l'app (lot 3), échéances H-3 et H (lot 4).
-- Aucune donnée existante n'est modifiée : seule la table interne des
-- déclarations est remplie, une fois, pour les côtés qui cherchent déjà.

-- 0. Déclaration d'imprévu --------------------------------------------------------
-- Une ligne par côté en imprévu. Interne : aucun accès de l'app (l'autre
-- titulaire ne doit jamais savoir qu'un côté cherche, D-001). Remplie une
-- seule fois à la création de la table (rejouer la migration ne recrée
-- jamais une déclaration effacée par un retour).

do $$
begin
  if to_regclass('public.imprevus_declares') is null then
    create table public.imprevus_declares (
      pacte_id uuid not null references public.pactes(id) on delete cascade,
      cote text not null check (cote in ('initiateur', 'destinataire')),
      declare_le timestamptz not null default clock_timestamp(),
      primary key (pacte_id, cote)
    );
    -- Côtés qui cherchent déjà (même règle que l'ancien état « cherche »),
    -- ou dont la place a déjà été prise (un désistement les remettra en
    -- recherche).
    insert into public.imprevus_declares (pacte_id, cote)
    select distinct r.pacte_id, r.cote
    from public.remplacants r
    join public.pactes p on p.id = r.pacte_id
    where p.statut = 'confirme'
      and r.retire_le is null
      and (r.selectionne or r.demande_statut in ('envoyee', 'refusee', 'desistee', 'acceptee'));
  end if;
end $$;

alter table public.imprevus_declares enable row level security;
revoke all on table public.imprevus_declares from public, anon, authenticated;

-- 1. Clôtures à mémoire -----------------------------------------------------------
-- 'acceptation' : demande en attente close par l'acceptation de fiche_acceptee
--                 (même côté) ; rouverte si cette personne se désiste.
-- 'autre_cote'  : fiche (prévue ou en attente : statut_avant) close parce que
--                 la même personne a pris la place de l'autre titulaire ;
--                 rendue à son état d'avant si elle se désiste.
-- Interne : le motif « autre_cote » révélerait au titulaire qui remplace
-- l'autre côté (D-001, D-012).

create table if not exists public.clotures_demandes (
  remplacant_id uuid primary key references public.remplacants(id) on delete cascade,
  motif text not null check (motif in ('acceptation', 'autre_cote')),
  fiche_acceptee uuid references public.remplacants(id) on delete set null,
  statut_avant text check (statut_avant is null or statut_avant = 'envoyee'),
  cloture_le timestamptz not null default clock_timestamp()
);
alter table public.clotures_demandes enable row level security;
revoke all on table public.clotures_demandes from public, anon, authenticated;

-- 2. Message à renvoyer -----------------------------------------------------------

alter table public.remplacants add column if not exists message_a_renvoyer boolean not null default false;

-- Insertion : rien d'autre que null / false (l'app n'a aucun droit UPDATE sur
-- remplacants, seulement INSERT). Identique à gel_a_h.sql, plus
-- message_a_renvoyer forcé à false.
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

  if auth.uid() is not null and v_pacte.date_retenue is not null
     and v_pacte.date_retenue <= now() then
    raise exception 'swend_passe';
  end if;

  new.selectionne := false;
  new.demande_statut := null;
  new.retire_le := null;
  new.message_a_renvoyer := false;

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
      and retire_le is null
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

-- Suivi de toute transition de demande_statut, quel que soit le chemin
-- (fonctions, moteurs, banc QA) :
--  * avant : le message à renvoyer n'a de sens que pour une demande en attente ;
--  * après : une demande (en attente, refusée, acceptée, désistée) déclare
--    l'imprévu de son côté s'il ne l'est pas ; une fiche qui quitte l'état
--    « clôturée » oublie sa clôture.

create or replace function public.suivre_demande_avant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.demande_statut is distinct from 'envoyee' then
    new.message_a_renvoyer := false;
  end if;
  return new;
end;
$$;
revoke execute on function public.suivre_demande_avant() from public, anon, authenticated;

drop trigger if exists trg_suivre_demande_avant on public.remplacants;
create trigger trg_suivre_demande_avant
  before update of demande_statut, message_a_renvoyer on public.remplacants
  for each row execute function public.suivre_demande_avant();

create or replace function public.suivre_demande_apres()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.demande_statut in ('envoyee', 'refusee', 'acceptee', 'desistee')
     and (tg_op = 'INSERT' or old.demande_statut is distinct from new.demande_statut) then
    insert into imprevus_declares (pacte_id, cote) values (new.pacte_id, new.cote)
    on conflict do nothing;
  end if;
  if tg_op = 'UPDATE' and old.demande_statut = 'cloturee'
     and new.demande_statut is distinct from 'cloturee' then
    delete from clotures_demandes where remplacant_id = new.id;
  end if;
  return null;
end;
$$;
revoke execute on function public.suivre_demande_apres() from public, anon, authenticated;

drop trigger if exists trg_suivre_demande_apres on public.remplacants;
create trigger trg_suivre_demande_apres
  after insert or update of demande_statut on public.remplacants
  for each row execute function public.suivre_demande_apres();

-- État d'un côté (rappels D-021, destination au clic) : la déclaration fait
-- foi. 'remplace' : quelqu'un a pris la place ; 'cherche' : imprévu déclaré,
-- personne n'a accepté ; 'normal' : sinon.
create or replace function public.etat_cote_titulaire(p_pacte_id uuid, p_cote text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (select 1 from remplacants
                 where pacte_id = p_pacte_id and cote = p_cote and selectionne) then 'remplace'
    when exists (select 1 from imprevus_declares
                 where pacte_id = p_pacte_id and cote = p_cote) then 'cherche'
    else 'normal'
  end
$$;
revoke execute on function public.etat_cote_titulaire(uuid, text) from public, anon, authenticated;

-- 3. Notifications (outils internes) ---------------------------------------------
-- Une seule porte par destinataire, payloads inchangés : la personne de
-- confiance → sa conversation avec le titulaire ; le titulaire → la
-- conversation avec la personne, ou la fiche du Swend.

create or replace function public.prenom_titulaire_de(p_remplacant_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(split_part(trim(
    case when r.cote = 'initiateur' then p.initiateur_nom else p.destinataire_nom end), ' ', 1), ''), 'Ton contact')
  from remplacants r join pactes p on p.id = r.pacte_id
  where r.id = p_remplacant_id
$$;
revoke execute on function public.prenom_titulaire_de(uuid) from public, anon, authenticated;

-- La personne de confiance (si elle a un compte).
create or replace function public.pousser_personne(p_remplacant_id uuid, p_titre text, p_corps text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profil uuid;
  v_titulaire_nom text;
begin
  select r.profil_id, case when r.cote = 'initiateur' then p.initiateur_nom else p.destinataire_nom end
    into v_profil, v_titulaire_nom
  from remplacants r join pactes p on p.id = r.pacte_id
  where r.id = p_remplacant_id;
  if v_profil is null then
    return;
  end if;
  perform notifier(v_profil, p_titre, p_corps,
    jsonb_build_object('type', 'chat', 'remplacant_id', p_remplacant_id,
                       'nom_interlocuteur', coalesce(v_titulaire_nom, '')));
end;
$$;
revoke execute on function public.pousser_personne(uuid, text, text) from public, anon, authenticated;

-- Le titulaire du côté de la fiche. p_vers_fiche : vers la fiche du Swend
-- (« Un imprévu ? ») plutôt que vers la conversation avec la personne.
create or replace function public.pousser_titulaire(
  p_remplacant_id uuid, p_titre text, p_corps text, p_vers_fiche boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_titulaire uuid;
  v_pacte uuid;
  v_nom_personne text;
begin
  select case when r.cote = 'initiateur' then p.initiateur_id else p.destinataire_id end,
         p.id, trim(coalesce(r.prenom, '') || ' ' || coalesce(r.nom, ''))
    into v_titulaire, v_pacte, v_nom_personne
  from remplacants r join pactes p on p.id = r.pacte_id
  where r.id = p_remplacant_id;
  if v_titulaire is null then
    return;
  end if;
  perform notifier(v_titulaire, p_titre, p_corps,
    case when p_vers_fiche
      then jsonb_build_object('type', 'pacte', 'pacte_id', v_pacte)
      else jsonb_build_object('type', 'chat', 'remplacant_id', p_remplacant_id,
                              'nom_interlocuteur', v_nom_personne) end);
end;
$$;
revoke execute on function public.pousser_titulaire(uuid, text, text, boolean) from public, anon, authenticated;

-- Le déclencheur ne garde que l'indisponibilité spontanée (D-008) : chaque
-- changement de demande est notifié par la fonction qui le fait, avec le
-- texte de son contexte (D-027).
create or replace function public.notifier_demande_remplacement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_personne text := coalesce(nullif(trim(new.prenom), ''), 'Une personne de confiance');
begin
  if new.profil_id is null
     or new.indisponible_spontanement is not distinct from old.indisponible_spontanement then
    return new;
  end if;
  if coalesce(current_setting('swend.annulation_en_cours', true), 'off') = 'on'
     or coalesce(current_setting('swend.gel_en_cours', true), 'off') = 'on' then
    return new;
  end if;
  perform pousser_titulaire(new.id, 'Swend',
    v_personne || case when new.indisponible_spontanement
      then ' ne sera pas disponible en cas d''imprévu pour ce Swend.'
      else ' est de nouveau disponible en cas d''imprévu pour ce Swend.' end);
  return new;
end;
$$;

-- 4. Fil : événements --------------------------------------------------------------

alter table public.evenements_fil drop constraint if exists evenements_fil_code_check;
alter table public.evenements_fil add constraint evenements_fil_code_check check (code in (
  'demande_envoyee', 'demande_annulee', 'demande_refusee', 'demande_acceptee',
  'desistement', 'demande_cloturee',
  'indisponibilite_signalee', 'disponibilite_retablie',
  'swend_commence',
  'demande_reactivee',   -- D-027 : la demande attend de nouveau une réponse
  'retour_titulaire'     -- D-027 : le titulaire pourra finalement être là
));

create or replace function public.journaliser_demande_remplacement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if new.demande_statut is not distinct from old.demande_statut then
    return new;
  end if;
  v_code := case
    when old.demande_statut is null and new.demande_statut = 'envoyee' then 'demande_envoyee'
    when old.demande_statut = 'envoyee' and new.demande_statut is null then
      case when coalesce(current_setting('swend.retour_en_cours', true), 'off') = 'on'
           then 'retour_titulaire' else 'demande_annulee' end
    when old.demande_statut = 'envoyee' and new.demande_statut = 'refusee' then 'demande_refusee'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'acceptee' then 'demande_acceptee'
    when old.demande_statut = 'acceptee' and new.demande_statut = 'desistee' then 'desistement'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'cloturee' then 'demande_cloturee'
    when old.demande_statut = 'cloturee' and new.demande_statut = 'envoyee' then 'demande_reactivee'
  end;
  if v_code is not null then
    insert into evenements_fil (remplacant_id, code) values (new.id, v_code);
  end if;
  return new;
end;
$$;

-- 5. Envoi des demandes ----------------------------------------------------------
-- Tout ou rien : une seule personne indisponible, et aucune demande ne part.
-- Mêmes contrôles et même ordre de verrouillage qu'avant (le Swend, puis
-- toutes ses fiches). Canal de remise : « notification » (compte Swend) ou
-- « message » (sans compte : le titulaire envoie le message d'urgence).

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
revoke execute on function public.envoyer_demandes_remplacement(uuid[]) from public, anon;
grant execute on function public.envoyer_demandes_remplacement(uuid[]) to authenticated;

-- Une seule personne : même règle (version de l'app actuelle).
create or replace function public.envoyer_demande_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform 1 from envoyer_demandes_remplacement(array[p_remplacant_id]);
end;
$$;
revoke execute on function public.envoyer_demande_remplacement(uuid) from public, anon;
grant execute on function public.envoyer_demande_remplacement(uuid) to authenticated;

-- Ajouter quelqu'un pendant l'imprévu et lui envoyer la demande : inchangé
-- (gel_a_h.sql), la push « On a besoin de toi » étant désormais envoyée ici.
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

-- Annuler une seule demande : action de l'app actuelle, retirée au lot 3
-- (D-027 : plus d'annulation demande par demande). Inchangée, sauf que le
-- côté sort de l'imprévu quand plus aucune demande n'y est en attente,
-- refusée ou désistée (même règle que l'ancien état « cherche »).
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

-- 6. « Je peux finalement venir » --------------------------------------------------
-- Avant toute acceptation de son côté : les demandes en attente sont closes
-- (elles redeviennent de simples personnes prévues, sollicitables lors d'un
-- prochain imprévu ; les refus restent des refus), le côté sort de l'imprévu.
-- Push aux personnes qui attendaient une réponse ; rien aux autres.

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
revoke execute on function public.je_peux_finalement_venir(uuid) from public, anon;
grant execute on function public.je_peux_finalement_venir(uuid) to authenticated;

-- 7. Réponse ---------------------------------------------------------------------
-- Acceptation : la première gagne (verrous inchangés). Les demandes en attente
-- du même côté sont closes en mémorisant cette acceptation ; les fiches de la
-- même personne de l'autre côté sont closes en mémorisant leur état d'avant
-- (sans push : rien ne doit révéler qui remplace l'autre titulaire).
-- Refus : le titulaire n'est prévenu que si c'était la dernière demande en
-- attente de son côté.

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
      v_personne || ' prendra ta place le jour J.');
  end if;
  foreach v_id in array v_closes loop
    perform pousser_personne(v_id, 'Plus besoin de répondre', 'La place a été prise pour ce Swend.');
  end loop;
end;
$$;

-- 8. Désistement ------------------------------------------------------------------
-- La personne qui avait accepté ne peut finalement plus venir (elle ne choisit
-- pas qui la remplace). Réactivation automatique :
--  * même côté : les demandes en attente avant cette acceptation repassent
--    « en attente » (push « Ta réponse est finalement attendue », ou message
--    à renvoyer par le titulaire si la personne n'a pas de compte) ; si la
--    personne a entre-temps pris la place de l'autre titulaire, sa fiche
--    garde la mémoire de son état pour son propre désistement ;
--  * même côté, fiches closes parce que leur personne remplaçait l'autre
--    titulaire et ne le fait plus : rendues à leur état d'avant ;
--  * autre côté : les fiches de la personne qui se désiste, closes par son
--    acceptation, retrouvent leur état d'avant si ce côté n'a personne ;
--  * une demande n'est rendue « en attente » que si son côté est toujours en
--    imprévu ; sinon la personne redevient simplement prévue ;
--  * clôtures sans mémoire (antérieures à D-027) : comportement d'avant, la
--    personne redevient sollicitable sans nouvelle demande.
-- Les refus restent des refus. Le titulaire est prévenu ; l'autre titulaire
-- jamais.

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

  v_personne := coalesce(nullif(trim(v_fiche.prenom), ''), 'Une personne de confiance');
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

-- 9. Message renvoyé ----------------------------------------------------------------
-- Le titulaire a relancé une personne sans compte dont la demande a été
-- réactivée (« Renvoyer le message à … ») : l'action disparaît.

create or replace function public.marquer_message_renvoye(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and ((r.cote = 'initiateur' and p.initiateur_id = v_uid)
        or (r.cote = 'destinataire' and p.destinataire_id = v_uid))
  ) then
    raise exception 'Non autorisé';
  end if;
  update remplacants set message_a_renvoyer = false
  where id = p_remplacant_id and message_a_renvoyer;
end;
$$;
revoke execute on function public.marquer_message_renvoye(uuid) from public, anon;
grant execute on function public.marquer_message_renvoye(uuid) to authenticated;

-- ================================================================================
-- Assertions
-- ================================================================================
do $$
begin
  -- Objets créés, déclencheurs actifs.
  if to_regclass('public.imprevus_declares') is null or to_regclass('public.clotures_demandes') is null
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('envoyer_demandes_remplacement', 'je_peux_finalement_venir', 'marquer_message_renvoye', 'pousser_personne', 'pousser_titulaire', 'prenom_titulaire_de', 'suivre_demande_avant', 'suivre_demande_apres')) <> 8
     or (select count(*) from pg_trigger where tgrelid = 'public.remplacants'::regclass
         and tgname in ('trg_suivre_demande_avant', 'trg_suivre_demande_apres') and tgenabled = 'O') <> 2 then
    raise exception 'D-027-01 : objets D-027 incomplets';
  end if;
  -- Les 9 fonctions ont bien été remplacées.
  if exists (select 1 from sauvegarde.d027_01_fonctions_20261012 s
             join pg_proc p on p.proname = s.nom and p.pronamespace = 'public'::regnamespace
             where s.md5_corps = md5(regexp_replace(p.prosrc, '\s+', ' ', 'g'))) then
    raise exception 'D-027-01 : une fonction n''a pas été remplacée';
  end if;
  -- Remplissage : exactement les côtés attendus.
  if (select count(*) from public.imprevus_declares) <> (select count(*) from d027_attendu)
     or exists (select pacte_id, cote from d027_attendu
                except select pacte_id, cote from public.imprevus_declares) then
    raise exception 'D-027-01 : remplissage des déclarations inattendu';
  end if;
  -- Aucune donnée existante modifiée.
  if exists (select 1 from sauvegarde.d027_01_remplacants_20261012 s
             join public.remplacants r on r.id = s.id
             where r.demande_statut is distinct from s.demande_statut
                or r.selectionne is distinct from s.selectionne
                or r.retire_le is distinct from s.retire_le
                or r.indisponible_spontanement is distinct from s.indisponible_spontanement)
     or exists (select 1 from public.remplacants where message_a_renvoyer)
     or (select count(*) from public.clotures_demandes) <> 0 then
    raise exception 'D-027-01 : une donnée existante a changé';
  end if;
  -- Droits : tables internes fermées, nouvelles actions pour authenticated seulement.
  if has_table_privilege('authenticated', 'public.imprevus_declares', 'select')
     or has_table_privilege('authenticated', 'public.clotures_demandes', 'select')
     or has_column_privilege('authenticated', 'public.remplacants', 'message_a_renvoyer', 'update')
     or has_function_privilege('authenticated', 'public.pousser_personne(uuid, text, text)', 'execute')
     or has_function_privilege('authenticated', 'public.pousser_titulaire(uuid, text, text, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.prenom_titulaire_de(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.etat_cote_titulaire(uuid, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.envoyer_demandes_remplacement(uuid[])', 'execute')
     or not has_function_privilege('authenticated', 'public.je_peux_finalement_venir(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.marquer_message_renvoye(uuid)', 'execute')
     or has_function_privilege('anon', 'public.envoyer_demandes_remplacement(uuid[])', 'execute')
     or has_function_privilege('anon', 'public.je_peux_finalement_venir(uuid)', 'execute')
     or has_function_privilege('anon', 'public.marquer_message_renvoye(uuid)', 'execute') then
    raise exception 'D-027-01 : droits inattendus';
  end if;
end $$;

commit;
