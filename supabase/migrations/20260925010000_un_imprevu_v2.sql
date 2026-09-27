-- Migration : "Un imprévu ?" v2 — règles validées le 25/09.
--
-- À exécuter dans le SQL Editor de Supabase, APRÈS un_imprevu.sql et
-- garde_fou_double_remplacement.sql (déjà exécutées). Sûre à ré-exécuter.
--
-- Principes :
--  * Toute transition d'état d'une demande passe désormais par une
--    fonction SECURITY DEFINER qui vérifie qui appelle et dans quel état
--    se trouve la fiche. Plus aucune écriture directe de l'app sur
--    `remplacants` n'est autorisée hormis l'INSERT (gestion de la liste),
--    lui-même normalisé par un trigger. Les règles "une seule personne
--    prend la place", "transfert définitif" et "personne engagée de
--    l'autre côté = indisponible" sont donc garanties par la base, pas
--    par l'interface.
--  * Toutes ces fonctions verrouillent d'abord la ligne `pactes`, puis
--    toutes les fiches `remplacants` du pacte (les deux côtés), toujours
--    dans cet ordre : deux actions concurrentes sur un même Swend sont
--    sérialisées, sans risque d'interblocage.
--  * Une personne présente des deux côtés est reconnue par son
--    `profil_id`. Dès qu'elle accepte d'un côté, ses fiches de l'autre
--    côté passent à `cloturee` (affichées "Indisponible"), sans
--    notification ni aucune information exposée à l'autre titulaire.

-- 1. Nouvelle valeur 'desistee' -----------------------------------------

do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.remplacants'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%demande_statut%'
  loop
    execute format('alter table public.remplacants drop constraint %I', c.conname);
  end loop;
end $$;

alter table remplacants
  add constraint remplacants_demande_statut_check
  check (demande_statut is null
         or demande_statut in ('envoyee', 'refusee', 'cloturee', 'acceptee', 'desistee'));

-- 2. Plus d'écriture directe (UPDATE/DELETE) depuis l'app ----------------
-- L'app passe par les fonctions ci-dessous. Les fonctions SECURITY
-- DEFINER existantes (handle_new_user, supprimer_pacte, triggers...)
-- tournent avec les droits du propriétaire et ne sont pas concernées.

revoke update on table remplacants from authenticated, anon;
revoke delete on table remplacants from authenticated, anon;

-- 3. Normalisation de toute nouvelle fiche ------------------------------
-- Une fiche naît toujours "jamais sollicitée" et non sélectionnée (aucun
-- moyen de s'auto-désigner par un INSERT forgé), son lien de compte est
-- recalculé côté serveur à partir du téléphone, et si la personne a déjà
-- pris la place de l'autre côté de ce Swend elle naît "indisponible".

create or replace function normaliser_nouveau_remplacant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform 1 from pactes where id = new.pacte_id for update;

  new.selectionne := false;
  new.demande_statut := null;
  new.profil_id := trouver_profil_par_telephone(trim(new.telephone));

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

drop trigger if exists trg_normaliser_nouveau_remplacant on remplacants;
create trigger trg_normaliser_nouveau_remplacant
  before insert on remplacants
  for each row execute function normaliser_nouveau_remplacant();

-- 4. Envoyer une demande (null → envoyee) --------------------------------

create or replace function envoyer_demande_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut into v_statut from pactes
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

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if exists (
    select 1 from remplacants
    where pacte_id = v_fiche.pacte_id and cote = v_fiche.cote and selectionne = true
  ) then
    raise exception 'place_deja_prise';
  end if;

  if v_fiche.selectionne or v_fiche.demande_statut is not null then
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
$$;

grant execute on function envoyer_demande_remplacement(uuid) to authenticated;

-- 5. Annuler une demande en attente (envoyee → null) ---------------------

create or replace function annuler_demande_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  perform 1 from pactes
  where id = v_fiche.pacte_id
    and ((v_fiche.cote = 'initiateur' and initiateur_id = v_uid)
      or (v_fiche.cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
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
$$;

grant execute on function annuler_demande_remplacement(uuid) to authenticated;

-- 6. Répondre à une demande (envoyee → refusee | acceptee) ---------------
-- Remplace la version du 25/09 (garde-fou) : verrouillage dans l'ordre
-- pacte puis fiches, relecture de la fiche APRÈS verrouillage (le perdant
-- d'une course voit donc forcément l'état final du gagnant), Swend
-- obligatoirement encore scellé, et clôture des fiches de la même
-- personne de l'autre côté.

create or replace function repondre_demande_remplacement(
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
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut into v_statut from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
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
      and profil_id = v_uid
      and (demande_statut is null or demande_statut = 'envoyee');
end;
$$;

grant execute on function repondre_demande_remplacement(uuid, boolean) to authenticated;

-- 7. Se désister après avoir accepté (acceptee → desistee) ---------------
-- Rouvre la recherche : les fiches clôturées du même côté redeviennent
-- disponibles (sauf celles d'une personne engagée de l'autre côté), les
-- refusées/désistées restent indisponibles. Les fiches de cette même
-- personne de l'autre côté, clôturées parce qu'elle s'était engagée ici,
-- redeviennent elles aussi disponibles (si personne n'a pris la place de
-- ce côté-là). Aucune notification envoyée par cette fonction.
-- `annuler_si_double_absence()` ignore le passage selectionne → false.

create or replace function se_desister_du_remplacement(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
  v_statut text;
begin
  select * into v_fiche from remplacants
  where id = p_remplacant_id and profil_id = v_uid;
  if not found then
    raise exception 'Non autorisé';
  end if;

  select statut into v_statut from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut <> 'confirme' then
    raise exception 'swend_inactif';
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
      and r.demande_statut = 'cloturee'
      and not (r.profil_id is not null and exists (
        select 1 from remplacants o
        where o.pacte_id = r.pacte_id and o.cote <> r.cote
          and o.profil_id = r.profil_id and o.selectionne = true));

  update remplacants r
    set demande_statut = null
    where r.pacte_id = v_fiche.pacte_id and r.cote <> v_fiche.cote
      and r.profil_id = v_uid
      and r.demande_statut = 'cloturee'
      and not exists (
        select 1 from remplacants o
        where o.pacte_id = r.pacte_id and o.cote = r.cote and o.selectionne = true);
end;
$$;

grant execute on function se_desister_du_remplacement(uuid) to authenticated;

-- 8. Retirer une personne de la liste ------------------------------------
-- Possible tant qu'aucune demande active ne lui est liée : jamais
-- sollicitée, refusée, clôturée ou désistée. Impossible si demande en
-- attente (annuler d'abord) ou si elle a accepté (transfert définitif).
-- Supprime aussi son fil de discussion.

create or replace function retirer_remplacant(p_remplacant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_fiche remplacants%rowtype;
begin
  select * into v_fiche from remplacants where id = p_remplacant_id;
  if not found then
    raise exception 'Non autorisé';
  end if;

  perform 1 from pactes
  where id = v_fiche.pacte_id
    and ((v_fiche.cote = 'initiateur' and initiateur_id = v_uid)
      or (v_fiche.cote = 'destinataire' and destinataire_id = v_uid))
  for update;
  if not found then
    raise exception 'Non autorisé';
  end if;

  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_fiche.selectionne or v_fiche.demande_statut in ('envoyee', 'acceptee') then
    raise exception 'retrait_impossible';
  end if;

  delete from messages where remplacant_id = p_remplacant_id;
  delete from remplacants where id = p_remplacant_id;
end;
$$;

grant execute on function retirer_remplacant(uuid) to authenticated;

-- 9. Ajouter quelqu'un pendant l'imprévu ET lui demander, en une action --
-- Tout ou rien : si la demande ne peut pas partir (place déjà prise,
-- personne engagée de l'autre côté...), l'ajout est annulé aussi.

create or replace function ajouter_et_demander_remplacement(
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
  v_id uuid;
  v_demande text;
begin
  if coalesce(trim(p_prenom), '') = '' or coalesce(trim(p_nom), '') = ''
     or coalesce(trim(p_telephone), '') = '' then
    raise exception 'champs_manquants';
  end if;

  select statut into v_statut from pactes
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
$$;

grant execute on function ajouter_et_demander_remplacement(uuid, text, text, text, text) to authenticated;

-- 10. Notifications à la personne sollicitée -----------------------------
-- Inchangé sauf un cas : une fiche clôturée parce que cette même personne
-- vient de prendre la place de l'AUTRE côté ne déclenche aucune
-- notification (elle vient d'accepter, et le texte "la place vient d'être
-- prise par quelqu'un d'autre" serait faux).

create or replace function notifier_demande_remplacement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_titulaire_nom text;
begin
  if new.demande_statut is not distinct from old.demande_statut then
    return new;
  end if;

  if new.profil_id is null then
    return new;
  end if;

  if new.demande_statut = 'envoyee' then
    select case when new.cote = 'initiateur' then initiateur_nom else destinataire_nom end
      into v_titulaire_nom
      from pactes where id = new.pacte_id;

    perform notifier(
      new.profil_id,
      'On a besoin de toi',
      coalesce(v_titulaire_nom, 'Quelqu''un') || ' te demande de prendre sa place pour un Swend.',
      jsonb_build_object(
        'type', 'chat',
        'remplacant_id', new.id,
        'nom_interlocuteur', coalesce(v_titulaire_nom, '')
      )
    );
  elsif new.demande_statut = 'cloturee' and old.demande_statut = 'envoyee' then
    if exists (
      select 1 from remplacants
      where pacte_id = new.pacte_id and cote <> new.cote
        and profil_id = new.profil_id and selectionne = true
    ) then
      return new;
    end if;

    select case when new.cote = 'initiateur' then initiateur_nom else destinataire_nom end
      into v_titulaire_nom
      from pactes where id = new.pacte_id;

    perform notifier(
      new.profil_id,
      'Swend',
      'C''est bon, quelqu''un a pu prendre la place.',
      jsonb_build_object(
        'type', 'chat',
        'remplacant_id', new.id,
        'nom_interlocuteur', coalesce(v_titulaire_nom, '')
      )
    );
  end if;

  return new;
end;
$$;
