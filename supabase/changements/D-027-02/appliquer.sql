-- D-027-02 — « En cas d'imprévu », lot 2 : annulation et conversations
-- (D-027). Une seule transaction : préconditions, migration
-- supabase/migrations/20261015000000_annulation_et_conversations.sql (copie
-- exacte), assertions. Toute assertion fausse annule tout. Aucune donnée
-- existante modifiée (colonnes ajoutées : motif NULL, nature 'apres_swend'
-- par défaut pour les chats existants).
begin;

-- 0. Préconditions --------------------------------------------------------------
do $$
begin
  -- Ordre des migrations testé : D-027-01 appliqué.
  if to_regclass('public.imprevus_declares') is null
     or not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'pousser_personne') then
    raise exception 'D-027-02 : D-027-01 pas encore appliqué (ordre des migrations)';
  end if;
  if to_regclass('public.fils_imprevu_fermes') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public'
                and ((table_name = 'pactes' and column_name = 'annule_motif')
                  or (table_name = 'chats_apres_swend' and column_name = 'nature')))
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('appliquer_annulation', 'ouvrir_chat_annulation', 'mes_chats_swend', 'fiche_acces_d023a', 'fil_conserve_apres_annulation', 'cle_paire_fil_imprevu')) then
    raise exception 'D-027-02 : déjà appliqué (en tout ou partie)';
  end if;
  -- Les 10 fonctions remplacées sont exactement celles relues en production
  -- le 15/10/2026 (corps normalisé).
  if (select count(*) from (values
    ('annuler_si_double_absence', 'c39f19ebc3b622dcbb657ca37fe199ae'),
    ('annuler_swend', '95d5c90fa45955ab8b58815f828ad057'),
    ('envoyer_message_apres_swend', '32be7513934ac244a0cab43eaa2af531'),
    ('fermer_chats_apres_nouveau_swend', 'c5159594fa64abc660daa60161c96624'),
    ('fiche_de_confiance_accessible', '6d610f3ac43051dd3ce0376672a7c965'),
    ('fil_ecriture_ouverte', 'b62fe26276082878d218536c0f944c59'),
    ('mes_chats_apres_swend', 'ef7f9efe2b9aec1334452236c0111be0'),
    ('proteger_annulation_pacte', 'c83814299a937e02f3743e74c43e791b'),
    ('retirer_remplacant', '3c85b3268d814d99e4240410054282a3'),
    ('telephone_titulaire_accessible', '4cff9f4bd8bfc6078ae4da9fe13d0580')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 10
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('annuler_si_double_absence', 'annuler_swend', 'envoyer_message_apres_swend', 'fermer_chats_apres_nouveau_swend', 'fiche_de_confiance_accessible', 'fil_ecriture_ouverte', 'mes_chats_apres_swend', 'proteger_annulation_pacte', 'retirer_remplacant', 'telephone_titulaire_accessible')) <> 10 then
    raise exception 'D-027-02 : les fonctions à remplacer diffèrent de celles relues (paquet à refaire)';
  end if;
  -- Déclencheurs dont le lot 2 remplace la fonction (eux-mêmes inchangés) :
  -- un seul, actif, définition relue le 15/10 (nom ignoré :
  -- on_remplacant_selectionne en production, trg_annuler_si_double_absence
  -- en QA) ; fermeture au scellement (2) et protection de l'annulation (1).
  if (select count(*) from pg_trigger t where t.tgrelid = 'public.remplacants'::regclass and not t.tgisinternal
      and t.tgfoid = 'public.annuler_si_double_absence()'::regprocedure) <> 1
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.remplacants'::regclass and not t.tgisinternal
         and t.tgenabled = 'O' and t.tgfoid = 'public.annuler_si_double_absence()'::regprocedure
         and regexp_replace(pg_get_triggerdef(t.oid), '^CREATE TRIGGER \S+ ', '')
             = 'AFTER INSERT OR UPDATE OF selectionne ON public.remplacants FOR EACH ROW EXECUTE FUNCTION annuler_si_double_absence()') <> 1
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.pactes'::regclass and t.tgenabled = 'O'
         and t.tgfoid = 'public.fermer_chats_apres_nouveau_swend()'::regprocedure) <> 2
     or (select count(*) from pg_trigger t where t.tgrelid = 'public.pactes'::regclass and t.tgenabled = 'O'
         and t.tgfoid = 'public.proteger_annulation_pacte()'::regprocedure) <> 1 then
    raise exception 'D-027-02 : déclencheurs différents de ceux relus (paquet à refaire)';
  end if;
  -- Aucune date de mise en service : la règle des conversations conservées
  -- ne doit rien rouvrir. Aucun Swend scellé puis annulé avec une
  -- conversation d'imprévu ne doit exister (0 le 15/10/2026) ; sinon,
  -- arbitrage produit nécessaire (redonner l'accès ou non) et paquet à refaire.
  if exists (select 1 from public.pactes p
             where p.statut in ('annule', 'annuleDoubleAbsence') and p.scelle_le is not null
               and exists (select 1 from public.remplacants r where r.pacte_id = p.id
                           and (exists (select 1 from public.evenements_fil e where e.remplacant_id = r.id and e.code = 'demande_envoyee')
                                or exists (select 1 from public.messages m where m.remplacant_id = r.id)))) then
    raise exception 'D-027-02 : un Swend annulé avec conversation existe déjà (arbitrage nécessaire)';
  end if;
  -- Sauvegarde faite (étape « sauvegarde » de ce paquet).
  if to_regclass('sauvegarde.d027_02_fonctions_20261015') is null
     or to_regclass('sauvegarde.d027_02_pactes_20261015') is null
     or to_regclass('sauvegarde.d027_02_chats_20261015') is null then
    raise exception 'D-027-02 : sauvegarde absente';
  end if;
end $$;

-- ================================================================================
-- Migration 20261015000000_annulation_et_conversations.sql (copie exacte)
-- ================================================================================

-- Migration : « En cas d'imprévu », lot 2 — annulation et conversations (D-027).
-- À exécuter après imprevu_etats_et_actions.sql. Sûre à ré-exécuter.
--
-- Contenu :
--  1. Annulation : un titulaire dont la place a déjà été prise ne peut plus
--     annuler lui-même (`remplacement_accepte`). Une seule fonction interne,
--     appliquer_annulation(), pour toute annulation (titulaire, double
--     remplacement ; plus tard H-3, H, raison opérationnelle) : demandes en
--     attente closes, statut, date et motif, notifications D-027, chat
--     d'annulation.
--  2. Chat d'annulation : un chat entre les deux titulaires seulement, ouvert
--     dans la même transaction que l'annulation, sans push d'ouverture. Même
--     infrastructure que le chat après le Swend (D-023b), distingué par
--     chats_apres_swend.nature = 'annulation' ; « Faire un nouveau Swend » et
--     la fermeture au scellement (D-023c) s'y appliquent tels quels.
--     mes_chats_apres_swend() (app publiée) ne renvoie que les chats après le
--     Swend ; mes_chats_swend() renvoie les deux natures (app du lot 3). Push
--     d'un message du chat d'annulation : « Swend annulé · Restaurant ».
--  3. Conversations d'imprévu après annulation : une personne réellement
--     sollicitée (une demande lui a été envoyée) ou avec qui une conversation
--     existe (au moins un message) garde sa conversation lisible et ouverte à
--     l'écriture, sans limite de date, jusqu'à ce qu'un nouveau Swend soit
--     scellé entre elle et ce titulaire. Une personne seulement prévue, sans
--     conversation, n'obtient rien.
--  4. Fermeture paire par paire : au scellement d'un Swend entre A et B, les
--     conversations d'imprévu conservées dont les deux membres sont A et B
--     sont fermées (lecture seule, événement « fil_ferme ») ; aucune autre.
--     Un tel scellement survenu avant l'annulation (après le scellement du
--     Swend annulé) ferme la conversation dès l'annulation : même issue quel
--     que soit l'ordre ; verrou consultatif par paire contre les courses.
--  5. D-024 inchangé : le numéro du titulaire suit exactement l'ancienne règle
--     d'accès (fiche_acces_d023a), découplée des droits de conversation.
--  6. Une fiche ne peut plus être retirée d'un Swend qui n'est plus en cours
--     (rien ne peut couper une conversation conservée).
--
-- Aucune donnée existante modifiée. Aucune date de mise en service : la règle
-- vaut pour toute annulation ; le paquet vérifie qu'aucun Swend annulé avec
-- conversation n'existe à l'exécution (0 en production le 15/10/2026).

-- 1. Annulation : motif ------------------------------------------------------------
-- annule_motif : 'titulaire' (annuler_swend), 'double_remplacement' ; réservé
-- au lot 4 et aux annulations opérationnelles : 'echeance_h3', 'echeance_h',
-- 'operationnelle'. annule_par : seulement pour une annulation par un
-- titulaire. Les annulations antérieures gardent leurs valeurs (motif NULL).

alter table public.pactes add column if not exists annule_motif text;
alter table public.pactes drop constraint if exists pactes_annule_motif_valeurs;
alter table public.pactes add constraint pactes_annule_motif_valeurs check (
  annule_motif is null
  or annule_motif in ('titulaire', 'double_remplacement', 'echeance_h3', 'echeance_h', 'operationnelle'));
alter table public.pactes drop constraint if exists pactes_annulation_complete;
alter table public.pactes add constraint pactes_annulation_complete check (
  (annule_par is null or annule_le is not null)
  and (annule_motif is null or annule_le is not null)
  and (annule_motif is distinct from 'titulaire' or annule_par is not null));

-- L'app ne peut ni poser ni changer l'auteur, la date ou le motif.
create or replace function public.proteger_annulation_pacte()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.annule_par is not null or new.annule_le is not null or new.annule_motif is not null then
        raise exception 'modification_interdite';
      end if;
    elsif new.annule_par is distinct from old.annule_par
       or new.annule_le is distinct from old.annule_le
       or new.annule_motif is distinct from old.annule_motif then
      raise exception 'modification_interdite';
    end if;
  end if;
  return new;
end;
$$;

-- 2. Chat d'annulation : nature ------------------------------------------------------

alter table public.chats_apres_swend add column if not exists nature text not null default 'apres_swend';
alter table public.chats_apres_swend drop constraint if exists chats_apres_swend_nature_valeurs;
alter table public.chats_apres_swend add constraint chats_apres_swend_nature_valeurs
  check (nature in ('apres_swend', 'annulation'));

-- Ouvre le chat d'annulation d'un Swend (verrous tenus par l'appelant).
-- Participants : les deux titulaires, prénom du compte (celui du Swend à
-- défaut). Jamais un remplaçant. Aucune push.
create or replace function public.ouvrir_chat_annulation(p_pacte_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  v_chat uuid;
begin
  select pa.initiateur_id, pa.destinataire_id,
         coalesce(nullif(trim(pi.prenom), ''), nullif(split_part(trim(pa.initiateur_nom), ' ', 1), ''), 'Swend') as prenom_i,
         coalesce(nullif(trim(pd.prenom), ''), nullif(split_part(trim(pa.destinataire_nom), ' ', 1), ''), 'Swend') as prenom_d
    into p
  from pactes pa
  left join profiles pi on pi.id = pa.initiateur_id
  left join profiles pd on pd.id = pa.destinataire_id
  where pa.id = p_pacte_id;
  if p.initiateur_id is null or p.destinataire_id is null or p.initiateur_id = p.destinataire_id then
    return null;
  end if;
  insert into chats_apres_swend (pacte_id, ouvre_le, ouvert_le, nature)
  values (p_pacte_id, clock_timestamp(), clock_timestamp(), 'annulation')
  on conflict (pacte_id) do nothing
  returning id into v_chat;
  if v_chat is null then
    return null;
  end if;
  insert into participants_chat_apres_swend (chat_id, profil_id, role, prenom_affiche)
  values (v_chat, p.initiateur_id, 'initiateur', p.prenom_i),
         (v_chat, p.destinataire_id, 'destinataire', p.prenom_d);
  return v_chat;
end;
$$;
revoke execute on function public.ouvrir_chat_annulation(uuid) from public, anon, authenticated;

-- Message dans un chat (D-023b) : la push du chat d'annulation dit « Swend
-- annulé · Restaurant » (jamais « Après le Swend »). Corps identique à
-- chat_apres_swend.sql, hors ce texte.
create or replace function public.envoyer_message_apres_swend(p_chat_id uuid, p_contenu text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_chat record;
  v_moi record;
  v_texte text;
  v_message uuid;
  v_restaurant text;
  v_autre record;
begin
  select c.id, c.pacte_id, c.ferme_le, c.nature into v_chat
  from chats_apres_swend c where c.id = p_chat_id;
  select id, prenom_affiche into v_moi
  from participants_chat_apres_swend where chat_id = p_chat_id and profil_id = v_uid;
  if v_uid is null or v_chat.id is null or v_moi.id is null then
    raise exception 'non_autorise';
  end if;
  if v_chat.ferme_le is not null then
    raise exception 'chat_ferme';
  end if;
  v_texte := regexp_replace(coalesce(p_contenu, ''), '^\s+|\s+$', '', 'g');
  if v_texte = '' then
    raise exception 'message_vide';
  end if;
  if char_length(v_texte) > 2000 then
    raise exception 'message_trop_long';
  end if;

  insert into messages_apres_swend (chat_id, genre, participant_id, contenu)
  values (p_chat_id, 'texte', v_moi.id, v_texte)
  returning id into v_message;

  -- Écrire, c'est avoir lu la conversation jusque-là.
  insert into lectures_chat_apres_swend (chat_id, profil_id, lu_le)
  values (p_chat_id, v_uid, clock_timestamp())
  on conflict (chat_id, profil_id) do update set lu_le = greatest(lectures_chat_apres_swend.lu_le, excluded.lu_le);

  select r.nom into v_restaurant
  from pactes pa left join restaurants r on r.id = pa.restaurant_id where pa.id = v_chat.pacte_id;
  for v_autre in
    select profil_id from participants_chat_apres_swend
    where chat_id = p_chat_id and profil_id is not null and profil_id <> v_uid order by role
  loop
    perform notifier(v_autre.profil_id, v_moi.prenom_affiche || ' vous a écrit',
      case when v_chat.nature = 'annulation' then 'Swend annulé · ' else 'Après le Swend · ' end
        || coalesce(v_restaurant, ''),
      jsonb_build_object('type', 'chat_apres_swend', 'chat_id', p_chat_id, 'pacte_id', v_chat.pacte_id));
  end loop;
  return v_message;
end;
$$;
revoke execute on function public.envoyer_message_apres_swend(uuid, text) from public, anon;
grant execute on function public.envoyer_message_apres_swend(uuid, text) to authenticated;

-- Tous mes chats entre participants d'un Swend, avec leur nature (app du
-- lot 3). Mêmes colonnes que mes_chats_apres_swend(), plus `nature`.
create or replace function public.mes_chats_swend()
returns table (
  chat_id uuid,
  pacte_id uuid,
  nature text,
  ouvert_le timestamptz,
  ferme_le timestamptz,
  motif_fermeture text,
  jamais_ouvert boolean,
  non_lus integer,
  dernier_message_le timestamptz,
  dernier_expediteur text,
  dernier_de_moi boolean,
  participants jsonb
)
language sql
stable
set search_path = public
as $$
  select c.id, c.pacte_id, c.nature, c.ouvert_le, c.ferme_le, c.motif_fermeture,
    l.lu_le is null,
    (select count(*)::integer from messages_apres_swend m
     left join participants_chat_apres_swend a on a.id = m.participant_id
     where m.chat_id = c.id and m.genre = 'texte'
       and a.profil_id is distinct from auth.uid()
       and (l.lu_le is null or m.created_at > l.lu_le)),
    d.created_at,
    case when d.id is null then null
         when d.profil_id is null then 'Compte supprimé'
         else d.prenom_affiche end,
    d.profil_id = auth.uid(),
    (select jsonb_agg(jsonb_build_object(
        'id', pa.id,
        'role', pa.role,
        'place_de', pa.place_de,
        'prenom', case when pa.profil_id is null then 'Compte supprimé' else pa.prenom_affiche end,
        'est_moi', pa.profil_id = auth.uid(),
        'compte_supprime', pa.profil_id is null)
      order by case pa.role when 'initiateur' then 1 when 'destinataire' then 2 else 3 end)
     from participants_chat_apres_swend pa where pa.chat_id = c.id)
  from chats_apres_swend c
  left join lectures_chat_apres_swend l on l.chat_id = c.id and l.profil_id = auth.uid()
  left join lateral (
    select m.id, m.created_at, a.profil_id, a.prenom_affiche
    from messages_apres_swend m
    join participants_chat_apres_swend a on a.id = m.participant_id
    where m.chat_id = c.id and m.genre = 'texte'
    order by m.created_at desc, m.id desc limit 1
  ) d on true
  where public.est_participant_chat_apres_swend(c.id)
  order by c.ouvert_le desc
$$;
revoke execute on function public.mes_chats_swend() from public, anon;
grant execute on function public.mes_chats_swend() to authenticated;

-- App publiée (lot 1) : chats après le Swend seulement. Un chat d'annulation
-- y serait présenté comme « Alors, ce Swend ? ». Corps identique à
-- chat_apres_swend.sql, plus le filtre sur la nature.
create or replace function public.mes_chats_apres_swend()
returns table (
  chat_id uuid,
  pacte_id uuid,
  ouvert_le timestamptz,
  ferme_le timestamptz,
  motif_fermeture text,
  jamais_ouvert boolean,
  non_lus integer,
  dernier_message_le timestamptz,
  dernier_expediteur text,
  dernier_de_moi boolean,
  participants jsonb
)
language sql
stable
set search_path = public
as $$
  select c.chat_id, c.pacte_id, c.ouvert_le, c.ferme_le, c.motif_fermeture, c.jamais_ouvert, c.non_lus,
         c.dernier_message_le, c.dernier_expediteur, c.dernier_de_moi, c.participants
  from public.mes_chats_swend() c
  where c.nature = 'apres_swend'
$$;
revoke execute on function public.mes_chats_apres_swend() from public, anon;
grant execute on function public.mes_chats_apres_swend() to authenticated;

-- 3. Conversations d'imprévu après annulation -------------------------------------
-- Fermeture paire par paire (table interne, aucun accès de l'app).

create table if not exists public.fils_imprevu_fermes (
  remplacant_id uuid primary key references public.remplacants(id) on delete cascade,
  motif text not null check (motif in ('nouveau_swend')),
  nouveau_pacte_id uuid references public.pactes(id) on delete set null,
  ferme_le timestamptz not null default clock_timestamp()
);
alter table public.fils_imprevu_fermes enable row level security;
revoke all on table public.fils_imprevu_fermes from public, anon, authenticated;

alter table public.evenements_fil drop constraint if exists evenements_fil_code_check;
alter table public.evenements_fil add constraint evenements_fil_code_check check (code in (
  'demande_envoyee', 'demande_annulee', 'demande_refusee', 'demande_acceptee',
  'desistement', 'demande_cloturee',
  'indisponibilite_signalee', 'disponibilite_retablie',
  'swend_commence',
  'demande_reactivee', 'retour_titulaire',
  'fil_ferme'   -- D-027 lot 2 : nouveau Swend scellé entre les deux membres
));

-- Règle d'accès D-023a, inchangée : fiche non retirée, et Swend en cours ou
-- remplaçant sélectionné. Sert désormais AUSSI, seule, au numéro du titulaire
-- (D-024) : les droits de conversation ci-dessous n'ouvrent aucun numéro.
create or replace function public.fiche_acces_d023a(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and r.retire_le is null
      and (r.selectionne
           or (p.statut not in ('annule', 'annuleDoubleAbsence', 'maintenu')
               and (p.date_retenue is null or p.date_retenue > now()))))
$$;
revoke execute on function public.fiche_acces_d023a(uuid) from public, anon, authenticated;

-- Verrou consultatif d'une paire de personnes (fermeture des conversations
-- d'imprévu conservées) : sérialise annulation et scellement entre elles.
create or replace function public.cle_paire_fil_imprevu(p_a uuid, p_b uuid)
returns bigint
language sql
immutable
set search_path = public
as $$
  select hashtextextended('fil_imprevu:' || least(p_a, p_b)::text || ':' || greatest(p_a, p_b)::text, 0)
$$;
revoke execute on function public.cle_paire_fil_imprevu(uuid, uuid) from public, anon, authenticated;

-- Conversation conservée après annulation : Swend scellé puis annulé, fiche
-- non retirée, et une conversation qui existe (une demande a été envoyée, ou
-- au moins un message). Fermée ou non (la fermeture n'ôte que l'écriture).
create or replace function public.fil_conserve_apres_annulation(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and r.retire_le is null
      and p.scelle_le is not null
      and p.statut in ('annule', 'annuleDoubleAbsence')
      and (exists (select 1 from evenements_fil e where e.remplacant_id = r.id and e.code = 'demande_envoyee')
           or exists (select 1 from messages m where m.remplacant_id = r.id)))
$$;
revoke execute on function public.fil_conserve_apres_annulation(uuid) from public, anon, authenticated;

-- Accès d'une personne de confiance à sa fiche (et donc au Swend, à sa
-- conversation, aux événements) : règle D-023a, ou conversation conservée.
create or replace function public.fiche_de_confiance_accessible(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fiche_acces_d023a(p_remplacant_id)
      or public.fil_conserve_apres_annulation(p_remplacant_id)
$$;
revoke execute on function public.fiche_de_confiance_accessible(uuid) from public, anon;
grant execute on function public.fiche_de_confiance_accessible(uuid) to authenticated;

-- Écriture : comme avant (Swend en cours, avant H), ou conversation conservée
-- après annulation et pas encore fermée par un nouveau scellement.
create or replace function public.fil_ecriture_ouverte(p_remplacant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and r.retire_le is null
      and p.scelle_le is not null
      and p.statut = 'confirme'
      and (p.date_retenue is null or p.date_retenue > now()))
  or (public.fil_conserve_apres_annulation(p_remplacant_id)
      and not exists (select 1 from fils_imprevu_fermes f where f.remplacant_id = p_remplacant_id))
$$;
revoke execute on function public.fil_ecriture_ouverte(uuid) from public, anon;
grant execute on function public.fil_ecriture_ouverte(uuid) to authenticated;

-- D-024 : numéro du titulaire, règle d'accès inchangée (D-023a), sans les
-- conversations conservées. Corps identique à gel_a_h.sql, hors la règle
-- appelée.
create or replace function public.telephone_titulaire_accessible(p_remplacant_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case when r.cote = 'initiateur' then pi.telephone else pd.telephone end
  from remplacants r
  join pactes p on p.id = r.pacte_id
  left join profiles pi on pi.id = p.initiateur_id
  left join profiles pd on pd.id = p.destinataire_id
  where r.id = p_remplacant_id
    and auth.uid() is not null
    and r.profil_id = auth.uid()
    and p.scelle_le is not null
    and public.fiche_acces_d023a(r.id)
$$;
revoke execute on function public.telephone_titulaire_accessible(uuid) from public, anon;
grant execute on function public.telephone_titulaire_accessible(uuid) to authenticated;

-- 4. Retirer une personne : seulement d'un Swend en cours ------------------------
-- Identique à gel_a_h.sql, plus le refus `swend_inactif` : sur un Swend
-- annulé, retirer une fiche couperait une conversation conservée.
create or replace function public.retirer_remplacant(p_remplacant_id uuid)
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
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes
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
  if v_statut in ('annule', 'annuleDoubleAbsence', 'maintenu') then
    raise exception 'swend_inactif';
  end if;

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_fiche.retire_le is not null then
    return;
  end if;
  if v_fiche.selectionne or v_fiche.demande_statut in ('envoyee', 'acceptee') then
    raise exception 'retrait_impossible';
  end if;

  update remplacants set retire_le = clock_timestamp() where id = p_remplacant_id;
end;
$$;

-- 5. Annulation ------------------------------------------------------------------------
-- appliquer_annulation(pacte, côté absent, motif, auteur) — verrous du Swend
-- puis de ses fiches tenus par l'appelant. Notifications (D-027), une seule
-- par personne, celle du remplaçant sélectionné en priorité :
--  * titulaire (motif 'titulaire', côté absent X) : l'autre titulaire, « Le
--    Swend est annulé / X ne pourra finalement pas être là. » ;
--  * double remplacement : chaque titulaire, « Le Swend est annulé. / Ni toi
--    ni Y ne pourrez finalement être là. » ;
--  * remplaçant sélectionné : « Le Swend est annulé / Tu n’auras finalement
--    pas besoin de prendre la place de T. » (T : titulaire de son côté) ;
--  * demande encore en attente (des deux côtés) : « Le Swend est annulé / Tu
--    n’as plus besoin de répondre. » ;
--  * celui qui annule, refus, désistements, personnes seulement prévues : rien.
-- Puis le chat d'annulation, sans push.

create or replace function public.appliquer_annulation(
  p_pacte_id uuid, p_cote_absent text, p_motif text, p_auteur uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  v_cloturees uuid[];
  v_fiche record;
  v_vus uuid[] := '{}';
  v_titulaire_fiche text;
begin
  select pa.id, pa.statut, pa.initiateur_id, pa.destinataire_id,
         coalesce(nullif(split_part(trim(pa.initiateur_nom), ' ', 1), ''), 'Ton contact') as prenom_i,
         coalesce(nullif(split_part(trim(pa.destinataire_nom), ' ', 1), ''), 'Ton contact') as prenom_d
    into p
  from pactes pa where pa.id = p_pacte_id;

  perform set_config('swend.annulation_en_cours', 'on', true);

  with c as (
    update remplacants set demande_statut = 'cloturee'
    where pacte_id = p_pacte_id and demande_statut = 'envoyee'
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_cloturees from c;

  update pactes
     set statut = case when p_motif = 'double_remplacement' then 'annuleDoubleAbsence' else 'annule' end,
         annule_par = p_auteur, annule_le = now(), annule_motif = p_motif
   where id = p_pacte_id;

  -- Titulaires.
  if p_motif = 'double_remplacement' then
    if p.initiateur_id is not null then
      perform notifier(p.initiateur_id, 'Le Swend est annulé.',
        'Ni toi ni ' || p.prenom_d || ' ne pourrez finalement être là.',
        jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
    end if;
    if p.destinataire_id is not null then
      perform notifier(p.destinataire_id, 'Le Swend est annulé.',
        'Ni toi ni ' || p.prenom_i || ' ne pourrez finalement être là.',
        jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
    end if;
  elsif p_cote_absent in ('initiateur', 'destinataire') then
    if p_cote_absent = 'initiateur' and p.destinataire_id is not null then
      perform notifier(p.destinataire_id, 'Le Swend est annulé',
        p.prenom_i || ' ne pourra finalement pas être là.',
        jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
    elsif p_cote_absent = 'destinataire' and p.initiateur_id is not null then
      perform notifier(p.initiateur_id, 'Le Swend est annulé',
        p.prenom_d || ' ne pourra finalement pas être là.',
        jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
    end if;
  end if;

  -- Personnes de confiance ayant un compte : remplaçant sélectionné d'abord,
  -- puis demandes closes par cette annulation ; une push par personne.
  for v_fiche in
    select r.id, r.cote, r.profil_id, r.selectionne
    from remplacants r
    where r.pacte_id = p_pacte_id and r.profil_id is not null
      and (r.selectionne or r.id = any (v_cloturees))
    order by r.selectionne desc, r.id
  loop
    continue when v_fiche.profil_id = any (v_vus);
    v_vus := v_vus || v_fiche.profil_id;
    if v_fiche.selectionne then
      v_titulaire_fiche := case when v_fiche.cote = 'initiateur' then p.prenom_i else p.prenom_d end;
      perform notifier(v_fiche.profil_id, 'Le Swend est annulé',
        'Tu n’auras finalement pas besoin de prendre la place ' || de_prenom(v_titulaire_fiche) || '.',
        jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
    else
      perform pousser_personne(v_fiche.id, 'Le Swend est annulé', 'Tu n’as plus besoin de répondre.');
    end if;
  end loop;

  -- Conversations conservées dont les deux membres ont déjà scellé un nouveau
  -- Swend entre eux depuis le scellement de celui-ci : fermées dès
  -- l'annulation, exactement comme si ce scellement venait après (même issue
  -- quel que soit l'ordre, cf. D-023c « ne s'ouvrira jamais »). Verrous de
  -- paire pris dans un ordre fixe, partagés avec la fermeture au scellement.
  for v_fiche in
    select distinct cle_paire_fil_imprevu(
             case when r.cote = 'initiateur' then p.initiateur_id else p.destinataire_id end, r.profil_id) as cle
    from remplacants r
    where r.pacte_id = p_pacte_id and r.profil_id is not null
      and public.fil_conserve_apres_annulation(r.id)
    order by 1
  loop
    perform pg_advisory_xact_lock(v_fiche.cle);
  end loop;
  with fermes as (
    insert into fils_imprevu_fermes (remplacant_id, motif, nouveau_pacte_id)
    select r.id, 'nouveau_swend', n.id
    from remplacants r
    join pactes pa on pa.id = r.pacte_id
    cross join lateral (
      select s.id from pactes s
      where s.id <> pa.id
        and s.scelle_le is not null and s.scelle_le > pa.scelle_le
        and ((s.initiateur_id = (case when r.cote = 'initiateur' then pa.initiateur_id else pa.destinataire_id end)
              and s.destinataire_id = r.profil_id)
          or (s.destinataire_id = (case when r.cote = 'initiateur' then pa.initiateur_id else pa.destinataire_id end)
              and s.initiateur_id = r.profil_id))
      order by s.scelle_le desc, s.id
      limit 1) n
    where r.pacte_id = p_pacte_id and r.profil_id is not null
      and public.fil_conserve_apres_annulation(r.id)
    on conflict (remplacant_id) do nothing
    returning remplacant_id
  )
  insert into evenements_fil (remplacant_id, code)
  select remplacant_id, 'fil_ferme' from fermes;

  perform ouvrir_chat_annulation(p_pacte_id);
  perform set_config('swend.annulation_en_cours', 'off', true);
end;
$$;
revoke execute on function public.appliquer_annulation(uuid, text, text, uuid) from public, anon, authenticated;

-- Annulation par un titulaire (D-022, révisée par D-027) : seulement s'il n'a
-- pas déjà été remplacé ; jusqu'à l'heure du Swend.
create or replace function public.annuler_swend(p_pacte_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  p record;
  v_cote text;
begin
  select pa.id, pa.statut, pa.date_retenue, pa.initiateur_id, pa.destinataire_id
    into p
  from pactes pa
  where pa.id = p_pacte_id
  for update of pa;
  if not found then
    raise exception 'swend_introuvable';
  end if;

  -- Seuls les deux titulaires originaux (jamais un remplaçant).
  v_cote := case when v_uid is not null and p.initiateur_id = v_uid then 'initiateur'
                 when v_uid is not null and p.destinataire_id = v_uid then 'destinataire' end;
  if v_cote is null then
    raise exception 'non_autorise';
  end if;
  if p.statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if p.date_retenue is null or p.date_retenue <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = p_pacte_id for update;

  if exists (select 1 from remplacants
             where pacte_id = p_pacte_id and cote = v_cote and selectionne) then
    raise exception 'remplacement_accepte';
  end if;

  perform appliquer_annulation(p_pacte_id, v_cote, 'titulaire', v_uid);
end;
$$;
revoke execute on function public.annuler_swend(uuid) from public, anon;
grant execute on function public.annuler_swend(uuid) to authenticated;

-- Double remplacement (D-005) : dès que les deux côtés ont une personne
-- sélectionnée, annulation par appliquer_annulation(). Une seule fois.
create or replace function public.annuler_si_double_absence()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.selectionne is not true then
    return new;
  end if;
  if not exists (select 1 from remplacants
                 where pacte_id = new.pacte_id and cote <> new.cote and selectionne = true) then
    return new;
  end if;
  if not exists (select 1 from pactes where id = new.pacte_id and statut = 'confirme') then
    return new; -- déjà annulé : rien de plus, aucune push en double
  end if;
  perform appliquer_annulation(new.pacte_id, null, 'double_remplacement', null);
  return new;
end;
$$;

-- 6. Fermeture au scellement (D-023c) : chats, et conversations d'imprévu par paire
-- a) et b) : identiques à nouveau_swend.sql (chats après le Swend et chats
-- d'annulation, toute nature). c) conversations d'imprévu conservées après
-- annulation dont les deux membres (titulaire du côté, personne de confiance)
-- sont exactement les deux titulaires du nouveau Swend : fermées, événement
-- « fil_ferme » ; aucune autre conversation. Aucune push.

create or replace function public.fermer_chats_apres_nouveau_swend()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  c_texte constant text := E'Un nouveau Swend a été scellé.\nCe chat est désormais fermé pour préserver le silence.';
  v_a uuid := new.initiateur_id;
  v_b uuid := new.destinataire_id;
  s record;
begin
  -- Rattrapage historique du scellement (scellage_et_negociation.sql) : pas
  -- un nouveau scellement.
  if v_a is null or v_b is null or v_a = v_b
     or coalesce(current_setting('swend.rattrapage_scellement', true), 'off') = 'on' then
    return null;
  end if;

  -- a) Chats pas encore ouverts.
  for s in
    select pa.id from pactes pa
    where pa.id <> new.id
      and (pa.initiateur_id in (v_a, v_b) or pa.destinataire_id in (v_a, v_b))
      and pa.statut = 'confirme' and pa.scelle_le is not null
      and pa.date_retenue is not null and pa.date_retenue < new.date_retenue
      and not exists (select 1 from chats_apres_swend c where c.pacte_id = pa.id)
      and not exists (select 1 from chats_apres_swend_jamais_ouverts j where j.pacte_id = pa.id)
      and (select count(distinct pp.profil_id) from participants_potentiels_chat_apres_swend(pa.id) pp
           where pp.profil_id in (v_a, v_b)) = 2
    order by pa.id
  loop
    perform 1 from pactes where id = s.id for update;
    continue when exists (select 1 from chats_apres_swend c where c.pacte_id = s.id);
    continue when (select count(distinct pp.profil_id) from participants_potentiels_chat_apres_swend(s.id) pp
                   where pp.profil_id in (v_a, v_b)) < 2;
    insert into chats_apres_swend_jamais_ouverts (pacte_id, motif, nouveau_pacte_id)
    values (s.id, 'nouveau_swend', new.id)
    on conflict (pacte_id) do nothing;
  end loop;

  -- b) Chats ouverts.
  with fermes as (
    update chats_apres_swend c
    set ferme_le = clock_timestamp(), motif_fermeture = 'nouveau_swend'
    where c.ferme_le is null
      and c.pacte_id <> new.id
      and exists (select 1 from participants_chat_apres_swend a where a.chat_id = c.id and a.profil_id = v_a)
      and exists (select 1 from participants_chat_apres_swend b where b.chat_id = c.id and b.profil_id = v_b)
    returning c.id, c.ferme_le
  )
  insert into messages_apres_swend (chat_id, genre, participant_id, contenu, created_at)
  select f.id, 'systeme', null, c_texte, f.ferme_le from fermes f;

  -- c) Conversations d'imprévu conservées après annulation, pour cette paire.
  -- Verrou de paire (après a et b) : une annulation simultanée attend, puis
  -- voit ce scellement (cf. appliquer_annulation).
  perform pg_advisory_xact_lock(cle_paire_fil_imprevu(v_a, v_b));
  with fermes as (
    insert into fils_imprevu_fermes (remplacant_id, motif, nouveau_pacte_id)
    select r.id, 'nouveau_swend', new.id
    from remplacants r join pactes pa on pa.id = r.pacte_id
    where pa.id <> new.id
      and pa.statut in ('annule', 'annuleDoubleAbsence')
      and r.profil_id is not null
      and public.fil_conserve_apres_annulation(r.id)
      and ((case when r.cote = 'initiateur' then pa.initiateur_id else pa.destinataire_id end) = v_a and r.profil_id = v_b
        or (case when r.cote = 'initiateur' then pa.initiateur_id else pa.destinataire_id end) = v_b and r.profil_id = v_a)
    on conflict (remplacant_id) do nothing
    returning remplacant_id
  )
  insert into evenements_fil (remplacant_id, code)
  select remplacant_id, 'fil_ferme' from fermes;

  return null;
end;
$$;
revoke execute on function public.fermer_chats_apres_nouveau_swend() from public, anon, authenticated;

-- ================================================================================
-- Assertions
-- ================================================================================
do $$
begin
  -- Objets créés.
  if to_regclass('public.fils_imprevu_fermes') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                    and table_name = 'pactes' and column_name = 'annule_motif')
     or not exists (select 1 from information_schema.columns where table_schema = 'public'
                    and table_name = 'chats_apres_swend' and column_name = 'nature')
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('appliquer_annulation', 'ouvrir_chat_annulation', 'mes_chats_swend', 'fiche_acces_d023a', 'fil_conserve_apres_annulation', 'cle_paire_fil_imprevu')) <> 6 then
    raise exception 'D-027-02 : objets D-027 lot 2 incomplets';
  end if;
  -- Les 10 fonctions sont exactement celles testées (corps normalisé).
  if (select count(*) from (values
    ('annuler_si_double_absence', 'ad2e9d2d81e68bfe6ad44acd6f7ac0d0'),
    ('annuler_swend', '049ffc128d473917fa03dcfaf35744f8'),
    ('envoyer_message_apres_swend', '72fc47459dc58c2fe317b698335a99a6'),
    ('fermer_chats_apres_nouveau_swend', '7ea52f3bd16ced80ebacddcec552ef09'),
    ('fiche_de_confiance_accessible', '10b81890c80d2a154f374fd58c5faa35'),
    ('fil_ecriture_ouverte', 'aa414126be7f5b25f4e5078816d72029'),
    ('mes_chats_apres_swend', '9113b88c045c81d7b75f69c372420f03'),
    ('proteger_annulation_pacte', 'fbf465112a8a83b1bb748b9a402acea6'),
    ('retirer_remplacant', '7c48a7431519497fa49593f22c604eb2'),
    ('telephone_titulaire_accessible', 'a3c60d57136e91714fe1d191dbdf2794')
  ) a(nom, md5)
      join pg_proc p on p.proname = a.nom and p.pronamespace = 'public'::regnamespace
      where md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) = a.md5) <> 10 then
    raise exception 'D-027-02 : une fonction n''est pas celle testée';
  end if;
  -- D-024 : la règle du numéro est exactement l'ancienne règle d'accès.
  if (select md5(regexp_replace(prosrc, '\s+', ' ', 'g')) from pg_proc
      where oid = 'public.fiche_acces_d023a(uuid)'::regprocedure)
     is distinct from (select md5_corps from sauvegarde.d027_02_fonctions_20261015
                       where nom = 'fiche_de_confiance_accessible') then
    raise exception 'D-027-02 : la règle d''accès du numéro (D-024) a changé';
  end if;
  -- Droits des fonctions remplacées inchangés.
  if exists (select 1 from sauvegarde.d027_02_fonctions_20261015 s
             join pg_proc p on p.proname = s.nom and p.pronamespace = 'public'::regnamespace
             where s.definition not like 'CHECK%'
               and (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a) is distinct from s.droits) then
    raise exception 'D-027-02 : droits d''une fonction remplacée modifiés';
  end if;
  -- Déclencheurs inchangés (mêmes noms, état et définitions que la sauvegarde).
  if exists (select 1 from sauvegarde.d027_02_fonctions_20261015 s
             where s.nom like 'declencheur %'
               and not exists (select 1 from pg_trigger t where not t.tgisinternal
                               and 'declencheur ' || t.tgname = s.nom and t.tgenabled::text = s.arguments
                               and pg_get_triggerdef(t.oid) = s.definition))
     or (select count(*) from pg_trigger t where not t.tgisinternal
         and t.tgfoid in ('public.annuler_si_double_absence()'::regprocedure,
                          'public.fermer_chats_apres_nouveau_swend()'::regprocedure,
                          'public.proteger_annulation_pacte()'::regprocedure))
        <> (select count(*) from sauvegarde.d027_02_fonctions_20261015 where nom like 'declencheur %') then
    raise exception 'D-027-02 : déclencheurs modifiés';
  end if;
  -- Aucune donnée existante modifiée.
  if exists (select 1 from sauvegarde.d027_02_pactes_20261015 s
             join public.pactes p on p.id = s.id
             where p.statut is distinct from s.statut or p.scelle_le is distinct from s.scelle_le
                or p.annule_par is distinct from s.annule_par or p.annule_le is distinct from s.annule_le)
     or exists (select 1 from public.pactes where annule_motif is not null)
     or exists (select 1 from sauvegarde.d027_02_chats_20261015 s
                join public.chats_apres_swend c on c.id = s.id
                where c.ferme_le is distinct from s.ferme_le or c.nature <> 'apres_swend')
     or (select count(*) from public.chats_apres_swend) <> (select count(*) from sauvegarde.d027_02_chats_20261015)
     or (select count(*) from public.fils_imprevu_fermes) <> 0 then
    raise exception 'D-027-02 : une donnée existante a changé';
  end if;
  -- Droits : table interne fermée, fonctions internes non exécutables par
  -- l'app, mes_chats_swend pour authenticated seulement.
  if has_table_privilege('authenticated', 'public.fils_imprevu_fermes', 'select')
     or has_table_privilege('anon', 'public.fils_imprevu_fermes', 'select')
     or has_table_privilege('authenticated', 'public.fils_imprevu_fermes', 'insert')
     or not (select relrowsecurity from pg_class where oid = 'public.fils_imprevu_fermes'::regclass)
     or has_function_privilege('authenticated', 'public.appliquer_annulation(uuid, text, text, uuid)', 'execute')
     or has_function_privilege('anon', 'public.appliquer_annulation(uuid, text, text, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ouvrir_chat_annulation(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fiche_acces_d023a(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fil_conserve_apres_annulation(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.cle_paire_fil_imprevu(uuid, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.mes_chats_swend()', 'execute')
     or has_function_privilege('anon', 'public.mes_chats_swend()', 'execute')
     or has_function_privilege('anon', 'public.mes_chats_apres_swend()', 'execute')
     or has_function_privilege('anon', 'public.annuler_swend(uuid)', 'execute') then
    raise exception 'D-027-02 : droits inattendus';
  end if;
  -- Contraintes.
  if pg_get_constraintdef((select oid from pg_constraint where conname = 'evenements_fil_code_check'
                           and conrelid = 'public.evenements_fil'::regclass)) not ilike '%fil_ferme%'
     or not exists (select 1 from pg_constraint where conname = 'pactes_annule_motif_valeurs'
                    and conrelid = 'public.pactes'::regclass)
     or not exists (select 1 from pg_constraint where conname = 'chats_apres_swend_nature_valeurs'
                    and conrelid = 'public.chats_apres_swend'::regclass)
     or pg_get_constraintdef((select oid from pg_constraint where conname = 'pactes_annulation_complete'
                              and conrelid = 'public.pactes'::regclass)) not ilike '%annule_motif%' then
    raise exception 'D-027-02 : contraintes inattendues';
  end if;
end $$;

commit;
