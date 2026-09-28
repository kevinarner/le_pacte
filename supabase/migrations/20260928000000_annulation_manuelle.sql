-- Migration : annulation manuelle d'un Swend scellé (D-022).
-- À exécuter après rappels_jour_j.sql (utilise date_rappel_fr(),
-- heure_rappel_fr()). Sûre à ré-exécuter.
--
-- Aucune donnée existante modifiée : deux colonnes ajoutées (annule_par,
-- annule_le), vides pour tous les Swends existants — pas de rattrapage, une
-- donnée inconnue plutôt qu'une attribution inventée.
--
-- Principes :
--  * Seuls les deux titulaires originaux peuvent annuler un Swend scellé,
--    jusqu'à l'heure du rendez-vous (date_retenue) — même si quelqu'un a
--    accepté de prendre leur place. Un remplaçant ne peut jamais annuler.
--  * Une seule porte d'entrée, atomique : annuler_swend(). Elle passe le
--    Swend à 'annule', clôt toutes les demandes encore en attente (des deux
--    côtés) et envoie les push validées. L'app ne peut plus changer
--    directement le statut d'un Swend scellé ou terminé.
--  * Aucun motif demandé ni transmis. L'identité d'un remplaçant n'est
--    jamais révélée à l'autre titulaire.
--  * Réservation (D-020) inchangée : rien n'est modifié automatiquement ;
--    la vue interne reservations_a_suivre affiche déjà « Annuler la
--    réservation au restaurant » si la table avait été réservée.
--  * Un Swend scellé (actif, passé ou annulé) ne peut plus être supprimé
--    par un utilisateur : il reste dans l'historique. La suppression interne
--    (service role / SQL Editor / banc QA) reste possible.

-- 0. Auteur et date d'une annulation manuelle ---------------------------------
-- Renseignés uniquement par annuler_swend(), dans la même opération que le
-- passage à 'annule'. NULL pour toute autre annulation (refus ou abandon
-- pendant la négociation, double remplacement) et pour les annulations
-- antérieures à cette migration (auteur inconnu).

alter table public.pactes add column if not exists annule_par uuid;
alter table public.pactes add column if not exists annule_le timestamptz;

alter table public.pactes drop constraint if exists pactes_annulation_complete;
alter table public.pactes add constraint pactes_annulation_complete
  check ((annule_par is null) = (annule_le is null));

-- 1. Annulation ---------------------------------------------------------------

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
  v_autre_id uuid;
  v_prenom_moi text;
  v_quand text;
  v_fiche record;
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

  -- Personnes de confiance ayant un compte : remplaçant accepté (on lui dit
  -- quel titulaire a annulé : l'expérience est terminée), ou demande qui
  -- vient d'être clôturée par cette annulation (sans détail). Une personne
  -- seulement prévue (ou dont la demande était déjà close) ne reçoit rien.
  for v_fiche in
    select r.id, r.cote, r.profil_id, r.selectionne
    from remplacants r
    where r.pacte_id = p_pacte_id and r.profil_id is not null
      and (r.selectionne or r.id = any (v_cloturees))
    order by r.selectionne desc, r.id
  loop
    if v_fiche.selectionne then
      perform notifier(v_fiche.profil_id, 'Le Swend est annulé',
        v_prenom_moi || ' a annulé le Swend du ' || v_quand || '.',
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
$$;
revoke execute on function public.annuler_swend(uuid) from public, anon;
grant execute on function public.annuler_swend(uuid) to authenticated;

-- 2. Pas de push parasite pendant l'annulation -------------------------------
-- notifier_demande_remplacement() : identique à rappels_jour_j.sql, plus
-- un retour immédiat pendant annuler_swend().

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
  -- Annulation manuelle du Swend (D-022) : annuler_swend() clôt les
  -- demandes en attente et envoie lui-même les push validées (« La demande
  -- n’est plus d’actualité ») ; aucune autre push ici (pas de « C'est bon,
  -- quelqu'un a pu prendre la place »).
  if coalesce(current_setting('swend.annulation_en_cours', true), 'off') = 'on' then
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
    -- Acceptation qui provoque le double remplacement : le titulaire reçoit
    -- à la place la push « Ton Swend est annulé » (annuler_si_double_absence),
    -- pas une acceptation contradictoire (l'événement reste dans le fil).
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
$$;


-- 3. Statut d'un Swend scellé ou terminé : protégé ---------------------------
-- L'app (authenticated) ne peut plus changer directement le statut d'un
-- Swend scellé (confirme) ni ranimer un Swend terminé ; l'annulation passe
-- par annuler_swend(). Les étapes de négociation (refus, abandon, choix de
-- date, scellage) restent inchangées. Les fonctions serveur (double
-- remplacement, annuler_swend) ne sont pas concernées.

create or replace function public.proteger_statut_pacte()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon')
     and new.statut is distinct from old.statut
     and old.statut in ('confirme', 'maintenu', 'annule', 'annuleDoubleAbsence') then
    raise exception 'statut_protege';
  end if;
  return new;
end;
$$;

-- Nom choisi pour passer après trg_verifier_negociation_date (ordre
-- alphabétique) : une contre-proposition tardive garde son message.
drop trigger if exists trg_verrou_statut_pacte on public.pactes;
create trigger trg_verrou_statut_pacte
  before update of statut on public.pactes
  for each row execute function public.proteger_statut_pacte();

-- 3 bis. Auteur et date d'annulation : jamais écrits par l'app ---------------
-- Même principe que la protection des participants (proteger_participants_
-- pacte) : refus explicite pour les rôles de l'app (authenticated, anon), à
-- la création comme à la modification. annuler_swend() (SECURITY DEFINER),
-- le service role et le SQL Editor ne sont pas concernés.

create or replace function public.proteger_annulation_pacte()
returns trigger
language plpgsql
set search_path = public
as $$
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
$$;

drop trigger if exists trg_proteger_annulation_pacte on public.pactes;
create trigger trg_proteger_annulation_pacte
  before insert or update on public.pactes
  for each row execute function public.proteger_annulation_pacte();

-- 4. Suppression : jamais un Swend scellé ------------------------------------
-- Même fonction qu'avant (supprimer_pacte.sql), plus le refus d'un Swend
-- scellé. Politique restrictive en plus : même un éventuel droit DELETE
-- direct de l'app ne pourrait pas supprimer un Swend scellé. La suppression
-- interne (rôle postgres / service role) reste possible.

create or replace function public.supprimer_pacte(p_pacte_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_est_partie boolean;
begin
  select exists (
    select 1 from pactes
    where id = p_pacte_id
      and (initiateur_id = v_uid or destinataire_id = v_uid)
  ) into v_est_partie;

  if not v_est_partie then
    raise exception 'Non autorisé à supprimer ce pacte';
  end if;

  if exists (select 1 from pactes where id = p_pacte_id and scelle_le is not null) then
    raise exception 'swend_scelle';
  end if;

  delete from messages
  where remplacant_id in (
    select id from remplacants where pacte_id = p_pacte_id
  );

  delete from remplacants where pacte_id = p_pacte_id;

  delete from pactes where id = p_pacte_id;
end;
$$;
grant execute on function public.supprimer_pacte(uuid) to authenticated;

drop policy if exists pactes_suppression_non_scelle on public.pactes;
create policy pactes_suppression_non_scelle on public.pactes
  as restrictive for delete to authenticated
  using (scelle_le is null);

-- Pour l'app : mes Swends scellés (titulaire), afin de ne proposer la
-- suppression que sur un Swend jamais scellé (scelle_le reste illisible).
create or replace function public.mes_swends_scelles()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from pactes
  where scelle_le is not null
    and auth.uid() is not null
    and (initiateur_id = auth.uid() or destinataire_id = auth.uid())
$$;
revoke execute on function public.mes_swends_scelles() from public, anon;
grant execute on function public.mes_swends_scelles() to authenticated;

-- Vérification (résultat affiché) ------------------------------------------
select 'Annulation disponible pour l''app, pas pour anon' as verification,
  (has_function_privilege('authenticated', 'public.annuler_swend(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.annuler_swend(uuid)', 'execute'))::text as resultat
union all
select 'Statut d''un Swend scellé protégé (garde en place)',
  exists (select 1 from pg_trigger where not tgisinternal and tgname = 'trg_verrou_statut_pacte')::text
union all
select 'Suppression d''un Swend scellé refusée (fonction + politique restrictive)',
  (exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pactes'
           and policyname = 'pactes_suppression_non_scelle' and permissive = 'RESTRICTIVE')
   and (select prosrc like '%swend_scelle%' from pg_proc where oid = 'public.supprimer_pacte(uuid)'::regprocedure))::text
union all
select 'Pas de push « quelqu''un a pu prendre la place » pendant une annulation',
  (select prosrc like '%swend.annulation_en_cours%' from pg_proc
   where oid = 'public.notifier_demande_remplacement()'::regprocedure)::text
union all
select 'Liste des Swends scellés disponible pour l''app',
  has_function_privilege('authenticated', 'public.mes_swends_scelles()', 'execute')::text
union all
select 'Auteur et date d''annulation enregistrés par annuler_swend() et protégés',
  ((select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'pactes'
      and column_name in ('annule_par', 'annule_le')) = 2
   and exists (select 1 from pg_trigger where not tgisinternal and tgname = 'trg_proteger_annulation_pacte')
   and (select prosrc like '%annule_par = v_uid%' from pg_proc where oid = 'public.annuler_swend(uuid)'::regprocedure))::text;
