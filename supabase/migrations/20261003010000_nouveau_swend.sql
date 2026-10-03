-- Migration : « Faire un nouveau Swend » et fermeture du chat après le Swend
-- (D-023c). À exécuter après fuseaux_horaires.sql. Sûre à ré-exécuter. Ne
-- modifie aucune donnée existante : seuls les scellements POSTÉRIEURS à son
-- exécution ferment des chats.
--
-- Règle centrale : dès qu'un nouveau Swend devient scellé (scelle_le passe de
-- NULL à une date, quel que soit le point d'entrée : « Faire un nouveau
-- Swend », « Créer un Swend » depuis l'accueil, SQL…), chaque chat après le
-- Swend déjà ouvert où ses DEUX titulaires sont participants ensemble est
-- fermé définitivement (lecture seule, historique conservé), avec un seul
-- message système. Une invitation ou une négociation ne ferme rien ; une
-- annulation ultérieure ne rouvre rien. Aucune push.
--
-- Contenu :
--  1. participants_potentiels_chat_apres_swend(pacte) : les deux titulaires
--     et les remplaçants sélectionnés non retirés — la logique du moteur
--     d'ouverture, désormais écrite une seule fois et utilisée par le moteur
--     ET par la fermeture.
--  2. chats_apres_swend_jamais_ouverts : un Swend passé (ou à venir) dont le
--     chat n'est pas encore ouvert quand un nouveau Swend, plus tardif, est
--     scellé entre deux de ses participants potentiels ne l'ouvrira jamais
--     (table interne, aucun accès de l'app).
--  3. ouvrir_chats_apres_swend() : utilise (1) et ignore les Swends de (2),
--     y compris en concurrence (contrôle après verrou du Swend).
--  4. Déclencheurs AFTER sur pactes (scellement à l'insertion ou à la
--     modification) : fermer_chats_apres_nouveau_swend().
--  5. Un Swend actif par paire, règle globale : swend_en_cours() (négociation
--     dont une date proposée est à venir, ou Swend scellé dont l'heure n'est
--     pas passée), swend_actif_entre(a, b), et le déclencheur
--     trg_verrou_un_swend_par_paire qui refuse toute création en doublon au
--     nom d'un utilisateur, quel que soit le point d'entrée
--     (`swend_deja_en_cours`).
--  6. Fonctions de l'app (depuis un chat ouvert, identité serveur, aucun
--     numéro renvoyé, D-024) : options_nouveau_swend(chat) et
--     creer_swend_depuis_chat(chat, participant, …).

-- 1. Participants potentiels (logique unique) ------------------------------------
-- Rang : initiateur 1, destinataire 2, remplaçants 3+ (ordre des fiches).
-- Plus d'un remplaçant : le moteur n'ouvre pas le chat (anomalie) ; la
-- fermeture les compte tous comme participants potentiels.

create or replace function public.participants_potentiels_chat_apres_swend(p_pacte_id uuid)
returns table (rang integer, role text, profil_id uuid, place_de text)
language sql
stable
set search_path = public
as $$
  select 1, 'initiateur', pa.initiateur_id, null::text from pactes pa where pa.id = p_pacte_id
  union all
  select 2, 'destinataire', pa.destinataire_id, null::text from pactes pa where pa.id = p_pacte_id
  union all
  select 2 + row_number() over (order by r.id)::integer, 'remplacant', r.profil_id, r.cote
  from remplacants r
  where r.pacte_id = p_pacte_id and r.selectionne and r.retire_le is null
  order by 1
$$;
revoke execute on function public.participants_potentiels_chat_apres_swend(uuid) from public, anon, authenticated;

-- 2. Chats qui ne s'ouvriront jamais ----------------------------------------------

create table if not exists public.chats_apres_swend_jamais_ouverts (
  pacte_id uuid primary key references public.pactes(id) on delete cascade,
  motif text not null check (motif in ('nouveau_swend')),
  -- Le Swend dont le scellement a empêché l'ouverture (trace).
  nouveau_pacte_id uuid references public.pactes(id) on delete set null,
  decide_le timestamptz not null default clock_timestamp()
);
alter table public.chats_apres_swend_jamais_ouverts enable row level security;
revoke all on table public.chats_apres_swend_jamais_ouverts from public, anon, authenticated;

-- 3. Moteur d'ouverture -------------------------------------------------------------
-- Identique à D-023b, sauf : participants lus par (1) ; Swend de (2) ignoré,
-- avant et après le verrou du Swend (un scellement concurrent qui l'a
-- bloqué est vu dès que son verrou est obtenu).

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
      and not exists (select 1 from chats_apres_swend_jamais_ouverts j where j.pacte_id = pa.id)
    order by pa.date_retenue, pa.id
  loop
    select statut, scelle_le, date_retenue
      into v_statut, v_scelle, v_date
    from pactes where id = p.id for update;
    perform 1 from remplacants where pacte_id = p.id for update;
    v_ouvre := ouverture_chat_apres_swend(v_date);
    continue when v_statut is distinct from 'confirme' or v_scelle is null
      or v_ouvre > p_maintenant or v_ouvre < v_service;
    continue when exists (select 1 from chats_apres_swend_jamais_ouverts j where j.pacte_id = p.id);

    select profil_id into v_initiateur
    from participants_potentiels_chat_apres_swend(p.id) where role = 'initiateur';
    select profil_id into v_destinataire
    from participants_potentiels_chat_apres_swend(p.id) where role = 'destinataire';
    select count(*) into v_nb_remplacants
    from participants_potentiels_chat_apres_swend(p.id) where role = 'remplacant';
    select pp.profil_id, pp.place_de as cote into v_remplacant
    from participants_potentiels_chat_apres_swend(p.id) pp where pp.role = 'remplacant'
    order by pp.rang limit 1;

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

-- 4. Fermeture au scellement --------------------------------------------------------
-- SECURITY DEFINER : le scellement vient de l'app (authenticated), qui n'a
-- aucun droit d'écriture sur les tables du chat.
--
-- a) Chats pas encore ouverts : tout Swend scellé (confirme), plus ancien que
--    le nouveau (date_retenue antérieure), sans chat, dont les deux
--    titulaires du nouveau Swend sont participants potentiels → ne s'ouvrira
--    jamais (l'un des deux en est forcément titulaire : deux remplaçants
--    sélectionnés, c'est un double remplacement, donc un Swend annulé, ou
--    une anomalie que le moteur n'ouvre pas). Verrou du Swend (ordre des id) puis nouveau contrôle : si le
--    moteur l'a ouvert entre-temps, b) le ferme.
-- b) Chats ouverts où les deux sont participants ensemble : une seule
--    instruction UPDATE … WHERE ferme_le IS NULL ; deux scellements
--    concurrents se sérialisent sur la ligne du chat, le second ne la voit
--    plus ouverte → un seul message système. Le message est daté de
--    l'instant de la fermeture (ordre chronologique), sans heure dans le texte.
-- Aucune push.

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

  return null;
end;
$$;
revoke execute on function public.fermer_chats_apres_nouveau_swend() from public, anon, authenticated;

drop trigger if exists trg_fermer_chats_nouveau_swend_insert on public.pactes;
create trigger trg_fermer_chats_nouveau_swend_insert
  after insert on public.pactes
  for each row when (new.scelle_le is not null)
  execute function public.fermer_chats_apres_nouveau_swend();

drop trigger if exists trg_fermer_chats_nouveau_swend_update on public.pactes;
create trigger trg_fermer_chats_nouveau_swend_update
  after update on public.pactes
  for each row when (old.scelle_le is null and new.scelle_le is not null)
  execute function public.fermer_chats_apres_nouveau_swend();

-- 5. Un Swend actif par paire -------------------------------------------------------
-- Actif : en négociation avec au moins une date proposée à venir, ou scellé
-- (confirme) et pas encore passé. Les deux titulaires, dans un sens ou dans
-- l'autre. Annulé, double remplacement, maintenu, passé : pas actif.

create or replace function public.swend_en_cours(p_statut text, p_dates_proposees jsonb, p_date_retenue timestamptz)
returns boolean
language sql
stable
set search_path = public
as $$
  select (p_statut in ('enAttenteChoixDateDestinataire', 'enAttenteChoixDateInitiateur', 'enAttenteReponse')
          and exists (select 1 from unnest(instants_proposes(p_dates_proposees)) d where d > now()))
      or (p_statut = 'confirme' and p_date_retenue > now())
$$;
revoke execute on function public.swend_en_cours(text, jsonb, timestamptz) from public, anon, authenticated;

create or replace function public.swend_actif_entre(p_a uuid, p_b uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1 from pactes p
    where ((p.initiateur_id = p_a and p.destinataire_id = p_b)
        or (p.initiateur_id = p_b and p.destinataire_id = p_a))
      and swend_en_cours(p.statut, p.dates_proposees, p.date_retenue))
$$;
revoke execute on function public.swend_actif_entre(uuid, uuid) from public, anon, authenticated;

-- Règle globale, quel que soit le point d'entrée (« Créer un Swend » depuis
-- l'accueil, « Faire un nouveau Swend », tout autre) : toute création d'un
-- Swend au nom d'un utilisateur (auth.uid() connu : app, fonctions appelées
-- par l'app) est refusée (`swend_deja_en_cours`) si un Swend est déjà en
-- cours entre les deux personnes. Destinataire sans compte : même règle, la
-- personne étant reconnue par son numéro canonique (mêmes initiateur et
-- numéro). Les écritures de service (SQL Editor, moteurs planifiés) ne sont
-- pas concernées. Verrou consultatif par paire : deux créations simultanées
-- se sérialisent, la seconde voit la première. Après
-- trg_normaliser_nouveau_pacte (destinataire retrouvé par son numéro) et
-- trg_verrou_delai_minimum_swend (ordre alphabétique) : leurs erreurs
-- restent prioritaires.
create or replace function public.verifier_un_swend_par_paire()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e164 text;
begin
  if auth.uid() is null then
    return new;
  end if;
  if new.destinataire_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'nouveau_swend:' || least(new.initiateur_id, new.destinataire_id)::text
      || ':' || greatest(new.initiateur_id, new.destinataire_id)::text, 0));
    if swend_actif_entre(new.initiateur_id, new.destinataire_id) then
      raise exception 'swend_deja_en_cours';
    end if;
  else
    v_e164 := normaliser_telephone(new.destinataire_telephone);
    perform pg_advisory_xact_lock(hashtextextended(
      'nouveau_swend:' || new.initiateur_id::text || ':' || coalesce(v_e164, ''), 0));
    if exists (
      select 1 from pactes p
      where p.initiateur_id = new.initiateur_id and p.destinataire_id is null
        and normaliser_telephone(p.destinataire_telephone) = v_e164
        and swend_en_cours(p.statut, p.dates_proposees, p.date_retenue)) then
      raise exception 'swend_deja_en_cours';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function public.verifier_un_swend_par_paire() from public, anon, authenticated;

drop trigger if exists trg_verrou_un_swend_par_paire on public.pactes;
create trigger trg_verrou_un_swend_par_paire
  before insert on public.pactes
  for each row execute function public.verifier_un_swend_par_paire();

-- 6. Fonctions de l'app ---------------------------------------------------------------

-- Les autres participants d'un chat ouvert avec qui je peux faire un nouveau
-- Swend : identifiant du participant (jamais un numéro ni un profil),
-- prénom affiché, et « Swend déjà en cours » (vérifié paire par paire).
-- Comptes supprimés exclus. Erreurs : non_autorise, chat_ferme.
create or replace function public.options_nouveau_swend(p_chat_id uuid)
returns table (participant_id uuid, prenom text, deja_en_cours boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ferme timestamptz;
begin
  if v_uid is null or not exists (
    select 1 from participants_chat_apres_swend where chat_id = p_chat_id and profil_id = v_uid
  ) then
    raise exception 'non_autorise';
  end if;
  select ferme_le into v_ferme from chats_apres_swend where id = p_chat_id;
  if v_ferme is not null then
    raise exception 'chat_ferme';
  end if;
  return query
    select a.id, a.prenom_affiche, swend_actif_entre(v_uid, a.profil_id)
    from participants_chat_apres_swend a
    where a.chat_id = p_chat_id and a.profil_id is not null and a.profil_id <> v_uid
    order by case a.role when 'initiateur' then 1 when 'destinataire' then 2 else 3 end;
end;
$$;
revoke execute on function public.options_nouveau_swend(uuid) from public, anon;
grant execute on function public.options_nouveau_swend(uuid) to authenticated;

-- Crée un Swend avec un autre participant de ce chat ouvert, depuis
-- « Faire un nouveau Swend ». La personne est désignée par son identifiant
-- de participant ; son numéro (profil, canonique) est recopié par la base et
-- n'est jamais renvoyé (D-024). Même Swend qu'à la création depuis
-- l'accueil : statut enAttenteChoixDateDestinataire, mêmes déclencheurs
-- (destinataire retrouvé par son numéro, forme canonique des dates, D-025b,
-- push d'invitation), et les personnes de confiance de l'initiateur dans la
-- même transaction (tout ou rien). D-025 appliqué ici explicitement : dans
-- une fonction SECURITY DEFINER, current_user n'est plus celui de l'app.
-- Erreurs : non_autorise, chat_ferme, swend_deja_en_cours, date_trop_proche
-- (+ celles des déclencheurs : date_sans_fuseau, personne_est_participant…).
create or replace function public.creer_swend_depuis_chat(
  p_chat_id uuid,
  p_participant_id uuid,
  p_type text,
  p_dates_proposees jsonb,
  p_restaurant_id uuid,
  p_remplacants jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ferme timestamptz;
  v_autre uuid;
  v_moi record;
  v_lui record;
  v_min date;
  v_pacte uuid;
  r jsonb;
begin
  if v_uid is null or not exists (
    select 1 from participants_chat_apres_swend where chat_id = p_chat_id and profil_id = v_uid
  ) then
    raise exception 'non_autorise';
  end if;
  select profil_id into v_autre
  from participants_chat_apres_swend where id = p_participant_id and chat_id = p_chat_id;
  if v_autre is null or v_autre = v_uid then
    raise exception 'non_autorise';
  end if;

  -- Une paire à la fois : deux créations simultanées pour la même paire se
  -- sérialisent ici ; la seconde voit la première.
  perform pg_advisory_xact_lock(hashtextextended(
    'nouveau_swend:' || least(v_uid, v_autre)::text || ':' || greatest(v_uid, v_autre)::text, 0));

  select ferme_le into v_ferme from chats_apres_swend where id = p_chat_id for share;
  if v_ferme is not null then
    raise exception 'chat_ferme';
  end if;
  if swend_actif_entre(v_uid, v_autre) then
    raise exception 'swend_deja_en_cours';
  end if;

  select prenom, nom into v_moi from profiles where id = v_uid;
  select prenom, nom, coalesce(telephone_e164, telephone) as telephone into v_lui
  from profiles where id = v_autre;
  if v_moi.prenom is null or v_lui.telephone is null then
    raise exception 'non_autorise';
  end if;

  -- D-025 : même règle que le déclencheur pour une création par l'app.
  v_min := date_minimale_nouveau_swend();
  if v_min is not null and exists (
    select 1 from unnest(instants_proposes(p_dates_proposees)) d
    where (d at time zone 'Europe/Paris')::date < v_min) then
    raise exception 'date_trop_proche' using detail = v_min::text;
  end if;

  insert into pactes (type, statut, dates_proposees, restaurant_id, initiateur_id,
                      initiateur_nom, destinataire_nom, destinataire_telephone, date_minimale)
  values (p_type, 'enAttenteChoixDateDestinataire', p_dates_proposees, p_restaurant_id, v_uid,
          btrim(coalesce(v_moi.prenom, '') || ' ' || coalesce(v_moi.nom, '')),
          btrim(coalesce(v_lui.prenom, '') || ' ' || coalesce(v_lui.nom, '')),
          v_lui.telephone, v_min)
  returning id into v_pacte;

  for r in select * from jsonb_array_elements(coalesce(p_remplacants, '[]'::jsonb))
  loop
    insert into remplacants (pacte_id, cote, prenom, nom, telephone, email)
    values (v_pacte, 'initiateur', coalesce(r->>'prenom', ''), coalesce(r->>'nom', ''),
            coalesce(r->>'telephone', ''), coalesce(r->>'email', ''));
  end loop;

  return v_pacte;
end;
$$;
revoke execute on function public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb) from public, anon;
grant execute on function public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb) to authenticated;

-- Vérification (résultat affiché) ------------------------------------------------
select 'D-023c : fermeture au scellement (insertion et modification), aucune push' as verification,
  ((select count(*) from pg_trigger where not tgisinternal and tgrelid = 'public.pactes'::regclass
      and tgname in ('trg_fermer_chats_nouveau_swend_insert', 'trg_fermer_chats_nouveau_swend_update')
      and tgenabled = 'O') = 2
   and (select prosrc not ilike '%notifier(%' from pg_proc
        where oid = 'public.fermer_chats_apres_nouveau_swend()'::regprocedure))::text as resultat
union all
select 'D-023c : chats jamais ouverts, table interne ; moteur et fermeture sur la même logique de participants',
  (to_regclass('public.chats_apres_swend_jamais_ouverts') is not null
   and not has_table_privilege('authenticated', 'public.chats_apres_swend_jamais_ouverts', 'select')
   and not has_table_privilege('anon', 'public.chats_apres_swend_jamais_ouverts', 'select')
   and (select prosrc ilike '%participants_potentiels_chat_apres_swend%' and prosrc ilike '%chats_apres_swend_jamais_ouverts%'
        from pg_proc where oid = 'public.ouvrir_chats_apres_swend(timestamptz)'::regprocedure)
   and not has_function_privilege('authenticated', 'public.participants_potentiels_chat_apres_swend(uuid)', 'execute')
   and not has_function_privilege('authenticated', 'public.swend_actif_entre(uuid, uuid)', 'execute'))::text
union all
select 'D-023c : un Swend en cours par paire, pour toute création au nom d''un utilisateur',
  (exists (select 1 from pg_trigger where not tgisinternal and tgrelid = 'public.pactes'::regclass
           and tgname = 'trg_verrou_un_swend_par_paire' and tgenabled = 'O')
   and not has_function_privilege('authenticated', 'public.swend_en_cours(text, jsonb, timestamptz)', 'execute')
   and not has_function_privilege('authenticated', 'public.verifier_un_swend_par_paire()', 'execute'))::text
union all
select 'D-023c : fonctions de l''app (comptes connectés seulement)',
  (has_function_privilege('authenticated', 'public.options_nouveau_swend(uuid)', 'execute')
   and has_function_privilege('authenticated', 'public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.options_nouveau_swend(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.creer_swend_depuis_chat(uuid, uuid, text, jsonb, uuid, jsonb)', 'execute'))::text;
