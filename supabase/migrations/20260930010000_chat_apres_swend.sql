-- Migration : chat après le Swend (D-023b).
-- À exécuter après confidentialite_telephones.sql. Sûre à ré-exécuter.
--
-- Après un Swend qui a eu lieu, le silence est levé : un chat s'ouvre entre
-- les deux titulaires d'origine et, s'il existe, le remplaçant sélectionné à
-- l'heure du Swend (3 personnes au plus).
--
-- Séparation complète avec les conversations d'imprévu : aucune des tables
-- messages, lectures_fil, evenements_fil n'est réutilisée ni modifiée, et
-- aucun message de ce chat ne passe par notifier_nouveau_message().
--
-- Contenu :
--  1. Borne de mise en service (pas de rattrapage) : un chat ne s'ouvre que
--     si son heure d'ouverture théorique est postérieure à la mise en service.
--  2. Tables : chats_apres_swend (un par Swend), participants (figés à
--     l'ouverture), messages (auteur = participant), lectures (individuelles).
--     ferme_le / motif_fermeture et les messages « système » sont prévus pour
--     D-023c mais inutilisés ici.
--  3. Heure d'ouverture (Europe/Paris) : H+3 si H+3 tombe le jour du Swend à
--     23:00 au plus tard ; sinon 10:00 le lendemain du Swend.
--  4. Moteur ouvrir_chats_apres_swend(p_maintenant) (pg_cron chaque minute,
--     planification à part : supabase/planification/chat_apres_swend_pg_cron.sql) :
--     Swend confirme, scellé, figé par D-023a (swends_figes), heure
--     d'ouverture atteinte ; chat + participants dans une seule transaction ;
--     push « Alors, ce Swend ? » si le retard est de 12 heures au plus.
--     Idempotent et sûr en concurrence (pacte_id unique). Plus d'un
--     remplaçant actif : chat non ouvert, anomalie enregistrée.
--  5. Fonctions pour l'app : envoyer un message, marquer comme lu, résumé de
--     mes chats. L'app n'a aucun droit d'écriture direct sur ces tables.
--  6. RLS : accès uniquement par la liste des participants (jamais par
--     remplacants), seulement après ouverture ; lectures : sa propre ligne.
--  7. Temps réel : la table des messages est ajoutée à la publication
--     supabase_realtime si elle existe (sans toucher au reste).
--
-- Ne modifie rien d'existant : ni pactes, ni remplacants, ni messages, ni
-- leurs politiques, ni est_remplacant_du_pacte(), ni les fonctions de D-023a.

-- 1. Borne de mise en service ---------------------------------------------------
-- Une seule ligne. Posée à la première exécution de cette migration, jamais
-- modifiée par une ré-exécution. Sans ligne, le moteur n'ouvre rien.

create table if not exists public.chat_apres_swend_service (
  id boolean primary key default true check (id),
  mise_en_service timestamptz not null default clock_timestamp()
);
alter table public.chat_apres_swend_service enable row level security;
revoke all on table public.chat_apres_swend_service from public, anon, authenticated;
insert into public.chat_apres_swend_service (id) values (true) on conflict (id) do nothing;

-- 2. Tables ------------------------------------------------------------------------

create table if not exists public.chats_apres_swend (
  id uuid primary key default gen_random_uuid(),
  pacte_id uuid not null unique references public.pactes(id) on delete cascade,
  ouvre_le timestamptz not null,
  ouvert_le timestamptz not null default clock_timestamp(),
  ferme_le timestamptz,
  motif_fermeture text check (motif_fermeture in ('nouveau_swend')),
  constraint chats_apres_swend_fermeture_complete check ((ferme_le is null) = (motif_fermeture is null))
);

create table if not exists public.participants_chat_apres_swend (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats_apres_swend(id) on delete cascade,
  -- NULL si le compte a été supprimé : l'historique reste, l'app affiche
  -- « Compte supprimé ».
  profil_id uuid references public.profiles(id) on delete set null,
  role text not null check (role in ('initiateur', 'destinataire', 'remplacant')),
  -- Pour le remplaçant : le côté dont il a pris la place.
  place_de text check (place_de in ('initiateur', 'destinataire')),
  -- Prénom du compte, figé à l'ouverture (jamais celui saisi sur la fiche).
  prenom_affiche text not null,
  constraint participants_chat_place_de check ((role = 'remplacant') = (place_de is not null)),
  constraint participants_chat_un_par_role unique (chat_id, role)
);
create unique index if not exists participants_chat_une_fois_par_compte
  on public.participants_chat_apres_swend (chat_id, profil_id) where profil_id is not null;

create table if not exists public.messages_apres_swend (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats_apres_swend(id) on delete cascade,
  -- 'texte' : écrit par un participant ; 'systeme' : réservé à D-023c
  -- (« Un nouveau Swend a été scellé… »), aucun auteur.
  genre text not null default 'texte' check (genre in ('texte', 'systeme')),
  participant_id uuid references public.participants_chat_apres_swend(id),
  contenu text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint messages_apres_swend_auteur check ((genre = 'texte') = (participant_id is not null)),
  constraint messages_apres_swend_contenu check (char_length(contenu) between 1 and 2000 and contenu ~ '\S')
);
create index if not exists messages_apres_swend_par_chat
  on public.messages_apres_swend (chat_id, created_at);

create table if not exists public.lectures_chat_apres_swend (
  chat_id uuid not null references public.chats_apres_swend(id) on delete cascade,
  profil_id uuid not null references public.profiles(id) on delete cascade,
  lu_le timestamptz not null default clock_timestamp(),
  primary key (chat_id, profil_id)
);

-- Anomalies détectées par le moteur (lisibles en SQL Editor / QA seulement).
create table if not exists public.anomalies_chat_apres_swend (
  pacte_id uuid primary key references public.pactes(id) on delete cascade,
  code text not null,
  detail text,
  detectee_le timestamptz not null default clock_timestamp()
);

-- 3. Heure d'ouverture ---------------------------------------------------------------

create or replace function public.ouverture_chat_apres_swend(p_date_retenue timestamptz)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select case
    when ((p_date_retenue + interval '3 hours') at time zone 'Europe/Paris')::date
           = (p_date_retenue at time zone 'Europe/Paris')::date
     and ((p_date_retenue + interval '3 hours') at time zone 'Europe/Paris')::time <= time '23:00'
      then p_date_retenue + interval '3 hours'
    else (((p_date_retenue at time zone 'Europe/Paris')::date + 1) + time '10:00') at time zone 'Europe/Paris'
  end
$$;

-- 6. Accès (défini avant les fonctions qui s'en servent) -----------------------------

-- La personne connectée participe-t-elle à ce chat ? SECURITY DEFINER : évite
-- que la politique des participants s'appelle elle-même.
create or replace function public.est_participant_chat_apres_swend(p_chat_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from participants_chat_apres_swend
    where chat_id = p_chat_id and profil_id = auth.uid())
$$;
revoke execute on function public.est_participant_chat_apres_swend(uuid) from public, anon;
grant execute on function public.est_participant_chat_apres_swend(uuid) to authenticated;

alter table public.chats_apres_swend enable row level security;
alter table public.participants_chat_apres_swend enable row level security;
alter table public.messages_apres_swend enable row level security;
alter table public.lectures_chat_apres_swend enable row level security;
alter table public.anomalies_chat_apres_swend enable row level security;

revoke all on table public.chats_apres_swend, public.participants_chat_apres_swend,
  public.messages_apres_swend, public.lectures_chat_apres_swend, public.anomalies_chat_apres_swend
  from public, anon, authenticated;
grant select on table public.chats_apres_swend, public.participants_chat_apres_swend,
  public.messages_apres_swend, public.lectures_chat_apres_swend to authenticated;

drop policy if exists chats_apres_swend_participants on public.chats_apres_swend;
create policy chats_apres_swend_participants on public.chats_apres_swend
  for select to authenticated using (public.est_participant_chat_apres_swend(id));

drop policy if exists participants_chat_apres_swend_participants on public.participants_chat_apres_swend;
create policy participants_chat_apres_swend_participants on public.participants_chat_apres_swend
  for select to authenticated using (public.est_participant_chat_apres_swend(chat_id));

drop policy if exists messages_apres_swend_participants on public.messages_apres_swend;
create policy messages_apres_swend_participants on public.messages_apres_swend
  for select to authenticated using (public.est_participant_chat_apres_swend(chat_id));

drop policy if exists lectures_chat_apres_swend_moi on public.lectures_chat_apres_swend;
create policy lectures_chat_apres_swend_moi on public.lectures_chat_apres_swend
  for select to authenticated using (profil_id = auth.uid());

-- 4. Moteur d'ouverture ------------------------------------------------------------------
-- Appelé chaque minute par pg_cron (et, dans le banc QA, avec un instant
-- contrôlé). Pour chaque Swend confirme, scellé, figé par D-023a, dont
-- l'heure d'ouverture est atteinte, postérieure à la mise en service, et
-- sans chat : verrou du Swend puis de ses fiches (même ordre que les autres
-- fonctions), participants, chat, push. Tout ce qui rend le chat visible est
-- dans la même transaction ; la push (pg_net, asynchrone) peut échouer sans
-- empêcher l'ouverture.

create or replace function public.ouvrir_chats_apres_swend(p_maintenant timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fenetre_push constant interval := interval '12 hours';
  v_service timestamptz;
  p record;
  v_statut text;
  v_scelle timestamptz;
  v_date timestamptz;
  v_initiateur uuid;
  v_destinataire uuid;
  v_ouvre timestamptz;
  v_nb_remplacants integer;
  v_remplacant record;
  v_prenom_i text;
  v_prenom_d text;
  v_prenom_r text;
  v_chat uuid;
  v_participant record;
  n integer := 0;
begin
  select mise_en_service into v_service from chat_apres_swend_service where id;
  if v_service is null then
    return 0;
  end if;

  for p in
    select pa.id from pactes pa
    join swends_figes f on f.pacte_id = pa.id
    where pa.statut = 'confirme'
      and pa.scelle_le is not null
      and pa.date_retenue is not null
      and ouverture_chat_apres_swend(pa.date_retenue) <= p_maintenant
      and ouverture_chat_apres_swend(pa.date_retenue) >= v_service
      and not exists (select 1 from chats_apres_swend c where c.pacte_id = pa.id)
      and not exists (select 1 from anomalies_chat_apres_swend a where a.pacte_id = pa.id)
    order by pa.date_retenue, pa.id
  loop
    select statut, scelle_le, date_retenue, initiateur_id, destinataire_id
      into v_statut, v_scelle, v_date, v_initiateur, v_destinataire
    from pactes where id = p.id for update;
    perform 1 from remplacants where pacte_id = p.id for update;
    v_ouvre := ouverture_chat_apres_swend(v_date);
    continue when v_statut is distinct from 'confirme' or v_scelle is null
      or v_ouvre > p_maintenant or v_ouvre < v_service;

    select count(*) into v_nb_remplacants
    from remplacants where pacte_id = p.id and selectionne and retire_le is null;
    select r.profil_id, r.cote into v_remplacant
    from remplacants r where r.pacte_id = p.id and r.selectionne and r.retire_le is null
    order by r.id limit 1;

    select nullif(trim(prenom), '') into v_prenom_i from profiles where id = v_initiateur;
    select nullif(trim(prenom), '') into v_prenom_d from profiles where id = v_destinataire;
    v_prenom_r := null;
    if v_nb_remplacants = 1 then
      select nullif(trim(prenom), '') into v_prenom_r from profiles where id = v_remplacant.profil_id;
    end if;

    -- Incohérences : le chat n'est pas ouvert, l'anomalie est enregistrée une
    -- fois (lisible en SQL) et signalée dans les journaux.
    if v_nb_remplacants > 1 or v_initiateur is null or v_destinataire is null
       or v_prenom_i is null or v_prenom_d is null
       or (v_nb_remplacants = 1 and v_prenom_r is null) then
      insert into anomalies_chat_apres_swend (pacte_id, code, detail)
      values (p.id,
        case when v_nb_remplacants > 1 then 'plusieurs_remplacants_actifs' else 'participant_introuvable' end,
        format('remplaçants actifs : %s ; initiateur : %s ; destinataire : %s',
               v_nb_remplacants, coalesce(v_initiateur::text, '-'), coalesce(v_destinataire::text, '-')))
      on conflict (pacte_id) do nothing;
      raise warning 'chat_apres_swend : Swend % non ouvert (remplaçants actifs : %)', p.id, v_nb_remplacants;
      continue;
    end if;

    insert into chats_apres_swend (pacte_id, ouvre_le, ouvert_le)
    values (p.id, v_ouvre, clock_timestamp())
    on conflict (pacte_id) do nothing
    returning id into v_chat;
    continue when v_chat is null;

    insert into participants_chat_apres_swend (chat_id, profil_id, role, prenom_affiche)
    values (v_chat, v_initiateur, 'initiateur', v_prenom_i),
           (v_chat, v_destinataire, 'destinataire', v_prenom_d);
    if v_nb_remplacants = 1 then
      insert into participants_chat_apres_swend (chat_id, profil_id, role, place_de, prenom_affiche)
      values (v_chat, v_remplacant.profil_id, 'remplacant', v_remplacant.cote, v_prenom_r);
    end if;

    if p_maintenant <= v_ouvre + c_fenetre_push then
      for v_participant in
        select profil_id from participants_chat_apres_swend
        where chat_id = v_chat and profil_id is not null order by role
      loop
        perform notifier(v_participant.profil_id, 'Alors, ce Swend ?',
          'Le silence est levé. Vous pouvez maintenant en reparler dans le chat.',
          jsonb_build_object('type', 'chat_apres_swend', 'chat_id', v_chat, 'pacte_id', p.id));
      end loop;
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.ouvrir_chats_apres_swend(timestamptz) from public, anon, authenticated;

-- 5. Fonctions pour l'app --------------------------------------------------------------

-- Envoie un message (texte / emoji, 2 000 caractères au plus, espaces de
-- début et de fin retirés). Push « [Prénom] vous a écrit » / « Après le
-- Swend · [Restaurant] » à chacun des autres participants, sans contenu.
-- Erreurs : non_autorise (pas participant, ou chat inexistant), chat_ferme,
-- message_vide, message_trop_long.
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
  select c.id, c.pacte_id, c.ferme_le into v_chat
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
      'Après le Swend · ' || coalesce(v_restaurant, ''),
      jsonb_build_object('type', 'chat_apres_swend', 'chat_id', p_chat_id, 'pacte_id', v_chat.pacte_id));
  end loop;
  return v_message;
end;
$$;
revoke execute on function public.envoyer_message_apres_swend(uuid, text) from public, anon;
grant execute on function public.envoyer_message_apres_swend(uuid, text) to authenticated;

-- Marque le chat comme lu par la personne connectée, et elle seule.
create or replace function public.marquer_chat_apres_swend_lu(p_chat_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from participants_chat_apres_swend where chat_id = p_chat_id and profil_id = v_uid
  ) then
    raise exception 'non_autorise';
  end if;
  insert into lectures_chat_apres_swend (chat_id, profil_id, lu_le)
  values (p_chat_id, v_uid, clock_timestamp())
  on conflict (chat_id, profil_id) do update set lu_le = greatest(lectures_chat_apres_swend.lu_le, excluded.lu_le);
end;
$$;
revoke execute on function public.marquer_chat_apres_swend_lu(uuid) from public, anon;
grant execute on function public.marquer_chat_apres_swend_lu(uuid) to authenticated;

-- Résumé de mes chats (accueil, Mes Swends, fiche) : aucun contenu de
-- message, aucun état de lecture des autres, aucun numéro. SECURITY INVOKER :
-- ne renvoie que ce que la RLS laisse lire.
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
  select c.id, c.pacte_id, c.ouvert_le, c.ferme_le, c.motif_fermeture,
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
revoke execute on function public.mes_chats_apres_swend() from public, anon;
grant execute on function public.mes_chats_apres_swend() to authenticated;

-- 7. Temps réel ---------------------------------------------------------------------------
-- Seulement si la publication Supabase existe, et une seule fois.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename = 'messages_apres_swend') then
    alter publication supabase_realtime add table public.messages_apres_swend;
  end if;
end $$;

-- Vérification (résultat affiché) ------------------------------------------
select 'Mise en service posée (aucun rattrapage avant cette date)' as verification,
  (select count(*) = 1 from public.chat_apres_swend_service)::text as resultat
union all
select 'Tables du chat après le Swend : lecture seule pour l''app, aucune écriture directe',
  (to_regclass('public.chats_apres_swend') is not null
   and to_regclass('public.participants_chat_apres_swend') is not null
   and to_regclass('public.messages_apres_swend') is not null
   and to_regclass('public.lectures_chat_apres_swend') is not null
   and has_table_privilege('authenticated', 'public.messages_apres_swend', 'select')
   and not has_table_privilege('authenticated', 'public.messages_apres_swend', 'insert, update, delete')
   and not has_table_privilege('authenticated', 'public.chats_apres_swend', 'insert, update, delete')
   and not has_table_privilege('authenticated', 'public.participants_chat_apres_swend', 'insert, update, delete')
   and not has_table_privilege('authenticated', 'public.lectures_chat_apres_swend', 'insert, update, delete')
   and not has_table_privilege('anon', 'public.messages_apres_swend', 'select')
   and not has_table_privilege('authenticated', 'public.anomalies_chat_apres_swend', 'select')
   and not has_table_privilege('authenticated', 'public.chat_apres_swend_service', 'select'))::text
union all
select 'Accès par la liste des participants uniquement (4 politiques)',
  ((select count(*) from pg_policies where schemaname = 'public' and policyname in (
      'chats_apres_swend_participants', 'participants_chat_apres_swend_participants',
      'messages_apres_swend_participants', 'lectures_chat_apres_swend_moi')) = 4)::text
union all
select 'Heure d''ouverture : 20h → 23h, 20h01 → lendemain 10h (Paris)',
  (public.ouverture_chat_apres_swend('2026-10-13 20:00 Europe/Paris') = '2026-10-13 23:00 Europe/Paris'::timestamptz
   and public.ouverture_chat_apres_swend('2026-10-13 20:01 Europe/Paris') = '2026-10-14 10:00 Europe/Paris'::timestamptz)::text
union all
select 'Moteur réservé au serveur ; fonctions de l''app en place',
  (not has_function_privilege('authenticated', 'public.ouvrir_chats_apres_swend(timestamptz)', 'execute')
   and has_function_privilege('authenticated', 'public.envoyer_message_apres_swend(uuid, text)', 'execute')
   and has_function_privilege('authenticated', 'public.marquer_chat_apres_swend_lu(uuid)', 'execute')
   and has_function_privilege('authenticated', 'public.mes_chats_apres_swend()', 'execute')
   and not has_function_privilege('anon', 'public.envoyer_message_apres_swend(uuid, text)', 'execute'))::text
union all
select 'Temps réel : messages du chat publiés (si la publication existe)',
  (not exists (select 1 from pg_publication where pubname = 'supabase_realtime')
   or exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
              and schemaname = 'public' and tablename = 'messages_apres_swend'))::text;
