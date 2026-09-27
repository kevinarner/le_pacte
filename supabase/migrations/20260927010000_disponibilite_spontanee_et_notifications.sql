-- Migration : indisponibilité spontanée (D-008) et notifications des
-- actions directes (D-015). À exécuter après fil_evenements_et_lectures.sql.
-- Sûre à ré-exécuter. Ne modifie aucune donnée existante (nouvelle
-- colonne à false pour toutes les fiches).
--
-- D-008 — Une personne de confiance simplement prévue (aucune demande,
-- pas sélectionnée) peut dire "Je ne serai pas disponible", puis revenir
-- sur sa décision ("Je suis finalement disponible"). Représenté par une
-- colonne dédiée, distincte de `demande_statut` : `demande_statut` reste
-- le cycle de vie d'une vraie demande (refus et désistement définitifs),
-- l'indisponibilité spontanée est un simple drapeau réversible, posé et
-- levé uniquement par la personne elle-même.
--
-- D-015 — Push (via notifier()) + événement dans le fil pour :
--   * la personne sollicitée → son titulaire : acceptation, refus,
--     désistement, indisponibilité spontanée, retour disponible ;
--   * le titulaire → la personne : annulation d'une demande en attente.
-- Inchangé : demande reçue, clôture automatique. Jamais rien à l'autre
-- titulaire du Swend.

-- 1. Colonne ---------------------------------------------------------------

alter table public.remplacants
  add column if not exists indisponible_spontanement boolean not null default false;

-- Toute fiche naît disponible : un INSERT forgé ne peut pas poser le drapeau.
create or replace function public.initialiser_disponibilite_spontanee()
returns trigger
language plpgsql
as $$
begin
  new.indisponible_spontanement := false;
  return new;
end;
$$;

drop trigger if exists trg_initialiser_disponibilite_spontanee on public.remplacants;
create trigger trg_initialiser_disponibilite_spontanee
  before insert on public.remplacants
  for each row execute function public.initialiser_disponibilite_spontanee();

-- 2. Signaler / lever l'indisponibilité (la personne elle-même) ----------
-- Même discipline de verrous que les autres fonctions "Un imprévu ?" :
-- la ligne `pactes`, puis toutes les fiches du pacte, puis relecture.

create or replace function public.signaler_indisponibilite(p_remplacant_id uuid)
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
  if not found or v_uid is null then
    raise exception 'Non autorisé';
  end if;

  select statut into v_statut from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut in ('annule', 'annuleDoubleAbsence', 'maintenu') then
    raise exception 'swend_inactif';
  end if;
  if v_fiche.indisponible_spontanement then
    return; -- déjà signalé : rien à faire, aucune notification en double
  end if;
  -- Seulement si simplement prévue : ni demande (quelle qu'elle soit), ni place prise.
  if v_fiche.selectionne or v_fiche.demande_statut is not null then
    raise exception 'demande_non_active';
  end if;

  update remplacants set indisponible_spontanement = true where id = p_remplacant_id;
end;
$$;

create or replace function public.signaler_disponibilite(p_remplacant_id uuid)
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
  if not found or v_uid is null then
    raise exception 'Non autorisé';
  end if;

  select statut into v_statut from pactes where id = v_fiche.pacte_id for update;
  perform 1 from remplacants where pacte_id = v_fiche.pacte_id for update;
  select * into v_fiche from remplacants where id = p_remplacant_id;

  if v_statut in ('annule', 'annuleDoubleAbsence', 'maintenu') then
    raise exception 'swend_inactif';
  end if;
  if not v_fiche.indisponible_spontanement then
    return; -- déjà disponible : rien à faire
  end if;

  update remplacants set indisponible_spontanement = false where id = p_remplacant_id;
end;
$$;

revoke execute on function public.signaler_indisponibilite(uuid) from public, anon;
revoke execute on function public.signaler_disponibilite(uuid) from public, anon;
grant execute on function public.signaler_indisponibilite(uuid) to authenticated;
grant execute on function public.signaler_disponibilite(uuid) to authenticated;

-- 3. Envoyer une demande : refusée si la personne s'est déclarée indisponible
-- (identique à un_imprevu_v2.sql, plus ce seul contrôle).

create or replace function public.envoyer_demande_remplacement(p_remplacant_id uuid)
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
$$;

grant execute on function public.envoyer_demande_remplacement(uuid) to authenticated;

-- 4. Événements du fil : deux nouveaux codes ------------------------------

alter table public.evenements_fil drop constraint if exists evenements_fil_code_check;
alter table public.evenements_fil add constraint evenements_fil_code_check check (code in (
  'demande_envoyee', 'demande_annulee', 'demande_refusee', 'demande_acceptee',
  'desistement', 'demande_cloturee',
  'indisponibilite_signalee',  -- false → true (la personne elle-même)
  'disponibilite_retablie'     -- true → false (la personne elle-même)
));

create or replace function public.journaliser_disponibilite_spontanee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.indisponible_spontanement is not distinct from old.indisponible_spontanement then
    return new;
  end if;
  insert into evenements_fil (remplacant_id, code)
  values (new.id, case when new.indisponible_spontanement
                       then 'indisponibilite_signalee' else 'disponibilite_retablie' end);
  return new;
end;
$$;

drop trigger if exists trg_journaliser_disponibilite_spontanee on public.remplacants;
create trigger trg_journaliser_disponibilite_spontanee
  after update of indisponible_spontanement on public.remplacants
  for each row execute function public.journaliser_disponibilite_spontanee();

-- 5. Notifications ---------------------------------------------------------
-- Reprend notifier_demande_remplacement() (un_imprevu_v2.sql) à
-- l'identique pour la demande reçue et la clôture automatique, et ajoute
-- les actions directes (D-015). Seules des transitions provoquées par la
-- personne elle-même (ou par son titulaire pour l'annulation) notifient :
-- les effets de bord (clôtures, réouvertures) ne notifient jamais un
-- titulaire, et l'autre titulaire n'est jamais destinataire.

create or replace function public.notifier_demande_remplacement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

drop trigger if exists trg_notifier_demande_remplacement on public.remplacants;
create trigger trg_notifier_demande_remplacement
  after update of demande_statut, indisponible_spontanement on public.remplacants
  for each row execute function public.notifier_demande_remplacement();

-- Vérification (résultat affiché) ------------------------------------------
select 'Colonne indisponible_spontanement présente' as verification,
  exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'remplacants'
            and column_name = 'indisponible_spontanement')::text as resultat
union all
select 'Écriture directe de la colonne impossible depuis l''app',
  (not has_column_privilege('authenticated', 'public.remplacants', 'indisponible_spontanement', 'update'))::text
union all
select 'Fonctions signaler_indisponibilite / signaler_disponibilite en place',
  (has_function_privilege('authenticated', 'public.signaler_indisponibilite(uuid)', 'execute')
   and has_function_privilege('authenticated', 'public.signaler_disponibilite(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.signaler_indisponibilite(uuid)', 'execute'))::text
union all
select 'Déclencheurs (initialisation, journal, notifications) en place',
  ((select count(*) from pg_trigger where not tgisinternal and tgname in (
     'trg_initialiser_disponibilite_spontanee',
     'trg_journaliser_disponibilite_spontanee',
     'trg_notifier_demande_remplacement')) = 3)::text;
