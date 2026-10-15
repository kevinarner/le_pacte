-- D-027-02 — rollback : objets D-027 lot 2 supprimés, les fonctions remplacées
-- remises à l'identique (définitions exactes relues en production le
-- 15/10/2026, conservées aussi dans sauvegarde.d027_02_fonctions_20261015),
-- droits d'origine. Une transaction. Aucune donnée supprimée :
--  - motifs d'annulation et conversations fermées copiés dans le schéma
--    `sauvegarde` avant la suppression de leur colonne / table ;
--  - chats d'annulation déjà ouverts : conservés, avec la colonne `nature`,
--    sa contrainte, mes_chats_swend() et mes_chats_apres_swend() filtrée
--    (sans quoi l'app publiée les montrerait comme des chats après le
--    Swend) ; sinon tout est retiré ;
--  - événements « fil_ferme » déjà écrits : contrainte des événements gardée
--    élargie ; sinon remise à l'identique ;
--  - annulations datées sans auteur (double remplacement D-027) : la
--    contrainte d'annulation garde la forme « auteur ⇒ date » (compatible
--    avec l'ancien code) ; sinon remise à l'identique.
-- Voir paquet.md (« Rollback ») pour l'ordre avec l'app.
begin;

do $$
begin
  if to_regclass('public.fils_imprevu_fermes') is null then
    raise exception 'D-027-02 rollback : D-027-02 n''est pas appliqué';
  end if;
  if to_regclass('sauvegarde.d027_02_fonctions_20261015') is null then
    raise exception 'D-027-02 rollback : sauvegarde absente';
  end if;
end $$;

-- 0. Traces conservées (schéma interne `sauvegarde`, un jeu par rollback).
do $$
declare
  v_suffixe text := to_char(clock_timestamp() at time zone 'UTC', 'YYYYMMDD_HH24MISS_US');
begin
  execute format('create table sauvegarde.%I as select id, annule_par, annule_le, annule_motif, now() as copie_le
                  from public.pactes where annule_motif is not null', 'd027_02_rollback_annulations_' || v_suffixe);
  execute format('create table sauvegarde.%I as select remplacant_id, motif, nouveau_pacte_id, ferme_le, now() as copie_le
                  from public.fils_imprevu_fermes', 'd027_02_rollback_fils_fermes_' || v_suffixe);
  execute format('revoke all on table sauvegarde.%I from public, anon, authenticated', 'd027_02_rollback_annulations_' || v_suffixe);
  execute format('revoke all on table sauvegarde.%I from public, anon, authenticated', 'd027_02_rollback_fils_fermes_' || v_suffixe);
end $$;

-- 1. Fonctions d'origine (pg_get_functiondef de la production, 15/10/2026).
CREATE OR REPLACE FUNCTION public.annuler_si_double_absence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p record;
  v_quand text;
  v_fiche record;
  v_titulaire text;
  v_autre text;
begin
  if new.selectionne is not true then
    return new;
  end if;
  if not exists (select 1 from remplacants
                 where pacte_id = new.pacte_id and cote <> new.cote and selectionne = true) then
    return new;
  end if;

  update pactes set statut = 'annuleDoubleAbsence'
  where id = new.pacte_id and statut <> 'annuleDoubleAbsence';
  if not found then
    return new; -- déjà annulé : rien de plus, aucune push en double
  end if;

  select pa.id, pa.date_retenue, pa.initiateur_id, pa.destinataire_id,
         split_part(trim(pa.initiateur_nom), ' ', 1) as prenom_initiateur,
         split_part(trim(pa.destinataire_nom), ' ', 1) as prenom_destinataire,
         r.nom as restaurant
    into p
  from pactes pa left join restaurants r on r.id = pa.restaurant_id
  where pa.id = new.pacte_id;
  v_quand := date_rappel_fr(p.date_retenue) || ' à ' || heure_rappel_fr(p.date_retenue)
             || ' · ' || coalesce(p.restaurant, 'le restaurant');

  if p.initiateur_id is not null then
    perform notifier(p.initiateur_id, 'Ton Swend est annulé',
      'Toi et ' || p.prenom_destinataire || ' avez chacun fait appel à quelqu’un pour prendre votre place. Le Swend du '
        || v_quand || ' est annulé.',
      jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
  end if;
  if p.destinataire_id is not null then
    perform notifier(p.destinataire_id, 'Ton Swend est annulé',
      'Toi et ' || p.prenom_initiateur || ' avez chacun fait appel à quelqu’un pour prendre votre place. Le Swend du '
        || v_quand || ' est annulé.',
      jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
  end if;

  for v_fiche in
    select r.cote, r.profil_id from remplacants r
    where r.pacte_id = new.pacte_id and r.selectionne and r.profil_id is not null
  loop
    if v_fiche.cote = 'initiateur' then
      v_titulaire := p.prenom_initiateur; v_autre := p.prenom_destinataire;
    else
      v_titulaire := p.prenom_destinataire; v_autre := p.prenom_initiateur;
    end if;
    perform notifier(v_fiche.profil_id, 'Le Swend est annulé',
      'Tu n’as finalement plus besoin de prendre la place de ' || v_titulaire || ' ' || v_quand
        || ' : ' || v_autre || ' a lui aussi fait appel à quelqu’un pour le remplacer.',
      jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
  end loop;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.annuler_swend(p_pacte_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  p record;
  v_cote text;
  v_autre_id uuid;
  v_prenom_moi text;
  v_quand text;
  v_fiche record;
  v_titulaire text;
  v_cloturees uuid[];
begin
  select pa.id, pa.statut, pa.date_retenue, pa.initiateur_id, pa.destinataire_id,
         pa.initiateur_nom, pa.destinataire_nom,
         split_part(trim(pa.initiateur_nom), ' ', 1) as prenom_initiateur,
         split_part(trim(pa.destinataire_nom), ' ', 1) as prenom_destinataire,
         r.nom as restaurant
    into p
  from pactes pa left join restaurants r on r.id = pa.restaurant_id
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
  perform set_config('swend.annulation_en_cours', 'on', true);

  -- Demandes encore en attente, des deux côtés : clôturées (événement
  -- « La demande n'est plus d'actualité » dans le fil).
  with c as (
    update remplacants set demande_statut = 'cloturee'
    where pacte_id = p_pacte_id and demande_statut = 'envoyee'
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_cloturees from c;

  update pactes set statut = 'annule', annule_par = v_uid, annule_le = now()
  where id = p_pacte_id;

  if v_cote = 'initiateur' then
    v_autre_id := p.destinataire_id; v_prenom_moi := p.prenom_initiateur;
  else
    v_autre_id := p.initiateur_id; v_prenom_moi := p.prenom_destinataire;
  end if;
  v_quand := date_rappel_fr(p.date_retenue) || ' à ' || heure_rappel_fr(p.date_retenue)
             || ' · ' || coalesce(p.restaurant, 'le restaurant');

  -- L'autre titulaire.
  if v_autre_id is not null then
    perform notifier(v_autre_id, 'Ton Swend est annulé',
      v_prenom_moi || ' a annulé votre Swend du ' || v_quand || '.',
      jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
  end if;

  -- Personnes de confiance ayant un compte : remplaçant accepté, ou demande
  -- qui vient d'être clôturée par cette annulation. Une personne seulement
  -- prévue (ou dont la demande était déjà close) ne reçoit rien.
  for v_fiche in
    select r.id, r.cote, r.profil_id, r.selectionne
    from remplacants r
    where r.pacte_id = p_pacte_id and r.profil_id is not null
      and (r.selectionne or r.id = any (v_cloturees))
    order by r.selectionne desc, r.id
  loop
    v_titulaire := case when v_fiche.cote = 'initiateur' then p.prenom_initiateur else p.prenom_destinataire end;
    if v_fiche.selectionne then
      perform notifier(v_fiche.profil_id, 'Le Swend est annulé',
        'Le Swend pour lequel tu devais prendre la place ' || de_prenom(v_titulaire) || ', ' || v_quand || ', est annulé.',
        jsonb_build_object('type', 'pacte', 'pacte_id', p.id));
    elsif not exists (
      -- Même personne des deux côtés (8.3) : une seule push par personne,
      -- celle du remplaçant accepté en priorité.
      select 1 from remplacants o
      where o.pacte_id = p_pacte_id and o.profil_id = v_fiche.profil_id and o.id <> v_fiche.id
        and (o.selectionne or (o.id = any (v_cloturees) and o.id < v_fiche.id))
    ) then
      perform notifier(v_fiche.profil_id, 'La demande n’est plus d’actualité', 'Le Swend a été annulé.',
        jsonb_build_object('type', 'chat', 'remplacant_id', v_fiche.id,
          'nom_interlocuteur', coalesce(case when v_fiche.cote = 'initiateur' then p.initiateur_nom else p.destinataire_nom end, '')));
    end if;
  end loop;

  perform set_config('swend.annulation_en_cours', 'off', true);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.fermer_chats_apres_nouveau_swend()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.fiche_de_confiance_accessible(p_remplacant_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and r.retire_le is null
      and (r.selectionne
           or (p.statut not in ('annule', 'annuleDoubleAbsence', 'maintenu')
               and (p.date_retenue is null or p.date_retenue > now()))))
$function$
;

CREATE OR REPLACE FUNCTION public.fil_ecriture_ouverte(p_remplacant_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from remplacants r join pactes p on p.id = r.pacte_id
    where r.id = p_remplacant_id
      and r.retire_le is null
      and p.scelle_le is not null
      and p.statut = 'confirme'
      and (p.date_retenue is null or p.date_retenue > now()))
$function$
;

CREATE OR REPLACE FUNCTION public.proteger_annulation_pacte()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.annule_par is not null or new.annule_le is not null then
        raise exception 'modification_interdite';
      end if;
    elsif new.annule_par is distinct from old.annule_par
       or new.annule_le is distinct from old.annule_le then
      raise exception 'modification_interdite';
    end if;
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.retirer_remplacant(p_remplacant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  if v_fiche.retire_le is not null then
    return;
  end if;
  if v_fiche.selectionne or v_fiche.demande_statut in ('envoyee', 'acceptee') then
    raise exception 'retrait_impossible';
  end if;

  update remplacants set retire_le = clock_timestamp() where id = p_remplacant_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.telephone_titulaire_accessible(p_remplacant_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when r.cote = 'initiateur' then pi.telephone else pd.telephone end
  from remplacants r
  join pactes p on p.id = r.pacte_id
  left join profiles pi on pi.id = p.initiateur_id
  left join profiles pd on pd.id = p.destinataire_id
  where r.id = p_remplacant_id
    and auth.uid() is not null
    and r.profil_id = auth.uid()
    and p.scelle_le is not null
    and public.fiche_de_confiance_accessible(r.id)
$function$
;

CREATE OR REPLACE FUNCTION public.envoyer_message_apres_swend(p_chat_id uuid, p_contenu text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

-- 2. Objets internes du lot 2.
drop table public.fils_imprevu_fermes;
drop function public.appliquer_annulation(uuid, text, text, uuid);
drop function public.ouvrir_chat_annulation(uuid);
drop function public.fil_conserve_apres_annulation(uuid);
drop function public.fiche_acces_d023a(uuid);
drop function public.cle_paire_fil_imprevu(uuid, uuid);

-- 3. Motif d'annulation (copié en 0).
alter table public.pactes drop constraint pactes_annule_motif_valeurs;
alter table public.pactes drop constraint pactes_annulation_complete;
alter table public.pactes drop column annule_motif;
do $$
begin
  if exists (select 1 from public.pactes where annule_le is not null and annule_par is null) then
    alter table public.pactes add constraint pactes_annulation_complete
      check (annule_par is null or annule_le is not null);
  else
    alter table public.pactes add constraint pactes_annulation_complete
      check ((annule_par is null) = (annule_le is null));
  end if;
end $$;

-- 4. Chats : nature et lecture, selon qu'un chat d'annulation existe.
do $$
begin
  if not exists (select 1 from public.chats_apres_swend where nature = 'annulation') then
    execute $restaurer$CREATE OR REPLACE FUNCTION public.mes_chats_apres_swend()
 RETURNS TABLE(chat_id uuid, pacte_id uuid, ouvert_le timestamp with time zone, ferme_le timestamp with time zone, motif_fermeture text, jamais_ouvert boolean, non_lus integer, dernier_message_le timestamp with time zone, dernier_expediteur text, dernier_de_moi boolean, participants jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
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
$function$
$restaurer$;
    drop function public.mes_chats_swend();
    alter table public.chats_apres_swend drop constraint chats_apres_swend_nature_valeurs;
    alter table public.chats_apres_swend drop column nature;
  end if;
end $$;

-- 5. Contrainte des événements du fil.
do $$
begin
  if not exists (select 1 from public.evenements_fil where code = 'fil_ferme') then
    alter table public.evenements_fil drop constraint evenements_fil_code_check;
    alter table public.evenements_fil add constraint evenements_fil_code_check check (code in (
      'demande_envoyee', 'demande_annulee', 'demande_refusee', 'demande_acceptee',
      'desistement', 'demande_cloturee',
      'indisponibilite_signalee', 'disponibilite_retablie',
      'swend_commence',
      'demande_reactivee', 'retour_titulaire'));
  end if;
end $$;

-- 6. Assertions.
do $$
declare
  v_garde_chats boolean := exists (select 1 from information_schema.columns where table_schema = 'public'
                                   and table_name = 'chats_apres_swend' and column_name = 'nature');
begin
  -- Fonctions : empreinte et droits de la sauvegarde (mes_chats_apres_swend
  -- seulement si les chats d'annulation n'imposent pas de la garder filtrée).
  if exists (select 1 from sauvegarde.d027_02_fonctions_20261015 s
             join pg_proc p on p.proname = s.nom and p.pronamespace = 'public'::regnamespace
             where s.definition not like 'CHECK%'
               and not (v_garde_chats and s.nom = 'mes_chats_apres_swend')
               and (md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')) is distinct from s.md5_corps
                    or (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a) is distinct from s.droits))
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
         and proname in ('annuler_si_double_absence', 'annuler_swend', 'envoyer_message_apres_swend', 'fermer_chats_apres_nouveau_swend', 'fiche_de_confiance_accessible', 'fil_ecriture_ouverte', 'mes_chats_apres_swend', 'proteger_annulation_pacte', 'retirer_remplacant', 'telephone_titulaire_accessible')) <> 10 then
    raise exception 'D-027-02 rollback : fonctions non remises à l''identique';
  end if;
  if to_regclass('public.fils_imprevu_fermes') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'public'
                and table_name = 'pactes' and column_name = 'annule_motif')
     or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('appliquer_annulation', 'ouvrir_chat_annulation', 'fiche_acces_d023a', 'fil_conserve_apres_annulation', 'cle_paire_fil_imprevu'))
     or (not v_garde_chats and exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mes_chats_swend')) then
    raise exception 'D-027-02 rollback : objets D-027 lot 2 restants';
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
    raise exception 'D-027-02 rollback : déclencheurs modifiés';
  end if;
  -- Aucune donnée perdue : Swends et chats toujours là.
  if (select count(*) from public.pactes) < (select count(*) from sauvegarde.d027_02_pactes_20261015)
     or (select count(*) from public.chats_apres_swend) < (select count(*) from sauvegarde.d027_02_chats_20261015) then
    raise exception 'D-027-02 rollback : données manquantes';
  end if;
end $$;

commit;
