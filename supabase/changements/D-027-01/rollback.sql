-- D-027-01 — rollback : objets D-027 lot 1 supprimés, les 9 fonctions remises à
-- l'identique (définitions des migrations testées, conservées aussi dans
-- sauvegarde.d027_01_fonctions_20261012), droits d'origine. Une transaction.
-- À combiner avec le retour à l'app précédente, AVANT ce rollback : voir
-- paquet.md. Ne touche à aucune demande : celles réactivées restent en
-- attente, celles closes restent closes.
begin;

do $$
begin
  if to_regclass('public.imprevus_declares') is null then
    raise exception 'D-027-01 rollback : D-027-01 n''est pas appliqué';
  end if;
end $$;

-- 1. Fonctions d'origine (pg_get_functiondef de la base testée, identique aux
--    migrations gel_a_h.sql et fil_evenements_et_lectures.sql).
CREATE OR REPLACE FUNCTION public.ajouter_et_demander_remplacement(p_pacte_id uuid, p_cote text, p_prenom text, p_nom text, p_telephone text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_statut text;
  v_date timestamptz;
  v_id uuid;
  v_demande text;
begin
  if coalesce(trim(p_prenom), '') = '' or coalesce(trim(p_nom), '') = ''
     or coalesce(trim(p_telephone), '') = '' then
    raise exception 'champs_manquants';
  end if;

  select statut, date_retenue into v_statut, v_date from pactes
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
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.annuler_demande_remplacement(p_remplacant_id uuid)
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

  if v_fiche.selectionne or v_fiche.demande_statut = 'acceptee' then
    raise exception 'deja_acceptee';
  end if;
  if v_fiche.demande_statut is distinct from 'envoyee' then
    raise exception 'demande_non_active';
  end if;

  update remplacants set demande_statut = null where id = p_remplacant_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.envoyer_demande_remplacement(p_remplacant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
  end if;
  if v_date is not null and v_date <= now() then
    raise exception 'swend_passe';
  end if;

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_fiche.retire_le is not null then
    raise exception 'demande_non_active';
  end if;

  if exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote and selectionne = true
  ) then
    raise exception 'place_deja_prise';
  end if;

  if v_fiche.selectionne or v_fiche.demande_statut is not null
     or v_fiche.indisponible_spontanement then
    raise exception 'personne_indisponible';
  end if;

  if v_fiche.profil_id is not null and exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote
      and profil_id = v_fiche.profil_id and selectionne = true
  ) then
    raise exception 'personne_indisponible';
  end if;

  update remplacants set demande_statut = 'envoyee' where id = p_remplacant_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.etat_cote_titulaire(p_pacte_id uuid, p_cote text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when exists (select 1 from remplacants
                 where pacte_id = p_pacte_id and cote = p_cote and selectionne) then 'remplace'
    when exists (select 1 from remplacants
                 where pacte_id = p_pacte_id and cote = p_cote and retire_le is null
                   and demande_statut in ('envoyee', 'refusee', 'desistee')) then 'cherche'
    else 'normal'
  end
$function$
;

CREATE OR REPLACE FUNCTION public.journaliser_demande_remplacement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code text;
begin
  if new.demande_statut is not distinct from old.demande_statut then
    return new;
  end if;
  v_code := case
    when old.demande_statut is null and new.demande_statut = 'envoyee' then 'demande_envoyee'
    when old.demande_statut = 'envoyee' and new.demande_statut is null then 'demande_annulee'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'refusee' then 'demande_refusee'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'acceptee' then 'demande_acceptee'
    when old.demande_statut = 'acceptee' and new.demande_statut = 'desistee' then 'desistement'
    when old.demande_statut = 'envoyee' and new.demande_statut = 'cloturee' then 'demande_cloturee'
  end;
  if v_code is not null then
    insert into evenements_fil (remplacant_id, code) values (new.id, v_code);
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.normaliser_nouveau_remplacant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.notifier_demande_remplacement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_titulaire_id uuid;
  v_titulaire_nom text;
  v_titulaire_prenom text;
  v_personne text := coalesce(nullif(trim(new.prenom), ''), 'Une personne de confiance');
  v_nom_personne text := trim(coalesce(new.prenom, '') || ' ' || coalesce(new.nom, ''));
  v_corps text;
begin
  if new.profil_id is null then
    return new;
  end if;
  -- Annulation manuelle (D-022) ou gel à H (D-023a) : la fonction appelante
  -- envoie elle-même les push validées ; aucune autre ici.
  if coalesce(current_setting('swend.annulation_en_cours', true), 'off') = 'on'
     or coalesce(current_setting('swend.gel_en_cours', true), 'off') = 'on' then
    return new;
  end if;

  select case when new.cote = 'initiateur' then initiateur_id else destinataire_id end,
         case when new.cote = 'initiateur' then initiateur_nom else destinataire_nom end
    into v_titulaire_id, v_titulaire_nom
    from pactes where id = new.pacte_id;
  v_titulaire_prenom := coalesce(nullif(split_part(trim(v_titulaire_nom), ' ', 1), ''), 'Ton contact');

  -- Indisponibilité spontanée : la personne → son titulaire.
  if new.indisponible_spontanement is distinct from old.indisponible_spontanement then
    if v_titulaire_id is not null then
      perform notifier(
        v_titulaire_id,
        'Swend',
        v_personne || case when new.indisponible_spontanement
          then ' ne sera pas disponible en cas d''imprévu pour ce Swend.'
          else ' est de nouveau disponible en cas d''imprévu pour ce Swend.' end,
        jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', v_nom_personne)
      );
    end if;
    return new;
  end if;

  if new.demande_statut is not distinct from old.demande_statut then
    return new;
  end if;

  if new.demande_statut = 'envoyee' then
    perform notifier(
      new.profil_id,
      'On a besoin de toi',
      coalesce(v_titulaire_nom, 'Quelqu''un') || ' te demande de prendre sa place pour un Swend.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  elsif new.demande_statut = 'cloturee' and old.demande_statut = 'envoyee' then
    if exists (
      select 1 from remplacants
      where pacte_id = new.pacte_id and cote <> new.cote
        and profil_id = new.profil_id and selectionne = true
    ) then
      return new;
    end if;
    perform notifier(
      new.profil_id,
      'Swend',
      'C''est bon, quelqu''un a pu prendre la place.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  -- Annulation par le titulaire → la personne sollicitée.
  elsif new.demande_statut is null and old.demande_statut = 'envoyee' then
    perform notifier(
      new.profil_id,
      'Swend',
      v_titulaire_prenom || ' a annulé sa demande.',
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', coalesce(v_titulaire_nom, ''))
    );

  -- Réponses et désistement de la personne → son titulaire.
  elsif v_titulaire_id is not null and (
        (old.demande_statut = 'envoyee' and new.demande_statut in ('acceptee', 'refusee'))
     or (old.demande_statut = 'acceptee' and new.demande_statut = 'desistee')) then
    if new.demande_statut = 'acceptee' and exists (
      select 1 from remplacants
      where pacte_id = new.pacte_id and cote <> new.cote and selectionne = true
    ) then
      return new;
    end if;
    v_corps := case new.demande_statut
      when 'acceptee' then v_personne || ' a accepté de prendre votre place.'
      when 'refusee' then v_personne || ' ne peut pas prendre votre place.'
      else v_personne || ' ne peut finalement plus prendre votre place.'
    end;
    perform notifier(
      v_titulaire_id,
      'Swend',
      v_corps,
      jsonb_build_object('type', 'chat', 'remplacant_id', new.id, 'nom_interlocuteur', v_nom_personne)
    );
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.repondre_demande_remplacement(p_remplacant_id uuid, p_accepte boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_date timestamptz;
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

  if not p_accepte then
    update remplacants set demande_statut = 'refusee' where id = p_remplacant_id;
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

  update remplacants
    set demande_statut = 'cloturee'
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote
      and id <> p_remplacant_id
      and demande_statut = 'envoyee';

  update remplacants
    set demande_statut = 'cloturee'
    where pacte_id = v_fiche.pacte_id and cote <> v_fiche.cote
      and profil_id = v_uid and retire_le is null
      and (demande_statut is null or demande_statut = 'envoyee');
end;
$function$
;

CREATE OR REPLACE FUNCTION public.se_desister_du_remplacement(p_remplacant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
  v_date timestamptz;
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

  update remplacants r
    set demande_statut = null
    where r.pacte_id = v_fiche.pacte_id and r.cote = v_fiche.cote
      and r.demande_statut = 'cloturee' and r.retire_le is null
      and not (r.profil_id is not null and exists (
        select 1 from remplacants o
        where o.pacte_id = r.pacte_id and o.cote <> r.cote
          and o.profil_id = r.profil_id and o.selectionne = true));

  update remplacants r
    set demande_statut = null
    where r.pacte_id = v_fiche.pacte_id and r.cote <> v_fiche.cote
      and r.profil_id = v_uid and r.retire_le is null
      and r.demande_statut = 'cloturee'
      and not exists (
        select 1 from remplacants o
        where o.pacte_id = r.pacte_id and o.cote = r.cote and o.selectionne = true);
end;
$function$
;

-- Droit d'origine de envoyer_demande_remplacement (D-027 l'avait restreint à
-- authenticated).
grant execute on function public.envoyer_demande_remplacement(uuid) to public;

-- 2. Objets D-027 supprimés.
drop trigger trg_suivre_demande_avant on public.remplacants;
drop trigger trg_suivre_demande_apres on public.remplacants;
drop function public.suivre_demande_avant();
drop function public.suivre_demande_apres();
drop function public.envoyer_demandes_remplacement(uuid[]);
drop function public.je_peux_finalement_venir(uuid);
drop function public.marquer_message_renvoye(uuid);
drop function public.pousser_personne(uuid, text, text);
drop function public.pousser_titulaire(uuid, text, text, boolean);
drop function public.prenom_titulaire_de(uuid);
drop table public.clotures_demandes;
drop table public.imprevus_declares;
alter table public.remplacants drop column message_a_renvoyer;

-- 3. Contrainte des événements : remise à l'identique s'il n'existe encore
--    aucun événement D-027 ; sinon conservée (élargie), pour ne supprimer
--    aucun historique de conversation (l'app précédente affiche un texte vide
--    pour un code inconnu).
do $$
begin
  if not exists (select 1 from public.evenements_fil where code in ('demande_reactivee', 'retour_titulaire')) then
    alter table public.evenements_fil drop constraint evenements_fil_code_check;
    alter table public.evenements_fil add constraint evenements_fil_code_check check (code in (
      'demande_envoyee', 'demande_annulee', 'demande_refusee', 'demande_acceptee',
      'desistement', 'demande_cloturee',
      'indisponibilite_signalee', 'disponibilite_retablie',
      'swend_commence'));
  else
    raise notice 'D-027-01 rollback : événements D-027 présents, contrainte élargie conservée';
  end if;
end $$;

-- 4. Contrôle : fonctions identiques à la sauvegarde.
do $$
begin
  if exists (select 1 from sauvegarde.d027_01_fonctions_20261012 s
             join pg_proc p on p.proname = s.nom and p.pronamespace = 'public'::regnamespace
             where s.md5_corps is not null
               and s.md5_corps <> md5(regexp_replace(p.prosrc, '\s+', ' ', 'g'))) then
    raise exception 'D-027-01 rollback : fonctions différentes de la sauvegarde';
  end if;
  if exists (select 1 from sauvegarde.d027_01_fonctions_20261012 s
             join pg_proc p on p.proname = s.nom and p.pronamespace = 'public'::regnamespace
             where s.droits is not null
               and s.droits is distinct from (select string_agg(a::text, ' ' order by a::text) from unnest(p.proacl) a)) then
    raise exception 'D-027-01 rollback : droits différents de la sauvegarde';
  end if;
end $$;

commit;
