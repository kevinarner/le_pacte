-- Migration : parcours "Un imprévu ?" — demander à une personne de
-- confiance de prendre la place, avec consentement (accepter/refuser).
--
-- À exécuter dans Supabase SQL Editor (aucun accès direct à la base
-- depuis Claude Code).
--
-- Principe : `remplacants.selectionne` continue de signifier exactement
-- ce qu'il signifiait déjà ("cette personne est celle qui se présentera
-- le jour J") — rien ne change pour `annuler_si_double_absence()`, qui
-- continue de tourner sans modification. Ce qui change : `selectionne`
-- ne passe plus à `true` directement au clic du titulaire, mais
-- seulement quand la personne sollicitée ACCEPTE, via la nouvelle
-- fonction `repondre_demande_remplacement()`.
--
-- Nouvelle colonne `demande_statut` sur `remplacants` :
--   null       = jamais sollicité pour cette tentative
--   'envoyee'  = demande envoyée, en attente de réponse
--   'refusee'  = la personne a refusé
--   'cloturee' = quelqu'un d'autre a accepté entre-temps
--   'acceptee' = cette personne a accepté (et selectionne = true)

alter table remplacants
  add column if not exists demande_statut text
    check (demande_statut is null or demande_statut in ('envoyee', 'refusee', 'cloturee', 'acceptee'));

-- Le titulaire a déjà le droit de modifier ses propres remplaçants
-- (déjà utilisé par l'app pour `selectionne`) ; on s'assure explicitement
-- que la nouvelle colonne est couverte par le même GRANT, par prudence
-- (leçon du projet : un GRANT manquant sur une nouvelle colonne casse
-- silencieusement l'écriture même quand une policy RLS l'autorise).
grant update (demande_statut) on remplacants to authenticated;

-- Répond à une demande de remplacement (accepter ou refuser), appelée
-- par la personne sollicitée elle-même. SECURITY DEFINER car :
--  1. elle doit pouvoir lire/modifier une ligne `remplacants` qui ne lui
--     appartient pas au sens RLS habituel (elle n'est "propriétaire" que
--     via `profil_id`, pas via `cote`) ;
--  2. en cas d'acceptation, elle doit aussi clôturer les autres demandes
--     en attente du même côté — des lignes que l'appelant (un simple
--     remplaçant) n'a normalement pas le droit de voir ni modifier.
--
-- Garantit qu'une seule personne peut accepter, même en cas de double
-- acceptation presque simultanée : `perform ... for update` verrouille
-- toutes les fiches remplaçants de ce côté avant de vérifier si la
-- place est déjà prise, ce qui sérialise deux appels concurrents.
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
  v_pacte_id uuid;
  v_cote text;
  v_demande_statut text;
  v_deja_pris boolean;
begin
  select pacte_id, cote, demande_statut
    into v_pacte_id, v_cote, v_demande_statut
  from remplacants
  where id = p_remplacant_id
    and profil_id = v_uid;

  if not found then
    raise exception 'Non autorisé';
  end if;

  if v_demande_statut is distinct from 'envoyee' then
    raise exception 'demande_non_active';
  end if;

  if not p_accepte then
    update remplacants set demande_statut = 'refusee' where id = p_remplacant_id;
    return;
  end if;

  -- Verrouille toutes les fiches remplaçants de ce côté du pacte : une
  -- éventuelle deuxième acceptation concurrente attendra ici que cette
  -- transaction se termine avant de relire l'état à jour.
  perform 1 from remplacants
    where pacte_id = v_pacte_id and cote = v_cote
    for update;

  select exists (
    select 1 from remplacants
    where pacte_id = v_pacte_id and cote = v_cote and selectionne = true
  ) into v_deja_pris;

  if v_deja_pris then
    update remplacants set demande_statut = 'cloturee'
      where id = p_remplacant_id and demande_statut = 'envoyee';
    raise exception 'place_deja_prise';
  end if;

  update remplacants
    set selectionne = true, demande_statut = 'acceptee'
    where id = p_remplacant_id;

  update remplacants
    set demande_statut = 'cloturee'
    where pacte_id = v_pacte_id and cote = v_cote
      and id <> p_remplacant_id
      and demande_statut = 'envoyee';
end;
$$;

grant execute on function repondre_demande_remplacement(uuid, boolean) to authenticated;

-- Notifie la personne sollicitée : quand on lui envoie une demande, et
-- quand sa demande en attente est clôturée parce que quelqu'un d'autre
-- a accepté. Réutilise le type de notification "chat" déjà géré côté
-- app (NotificationService._gererClicNotification) : au clic, ouvre
-- directement le fil de discussion concerné, où la demande est traitée.
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
    select case when new.cote = 'initiateur' then initiateur_nom else destinataire_nom end
      into v_titulaire_nom
      from pactes where id = new.pacte_id;

    perform notifier(
      new.profil_id,
      'Swend',
      'La place vient d''être prise par quelqu''un d''autre.',
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

drop trigger if exists trg_notifier_demande_remplacement on remplacants;
create trigger trg_notifier_demande_remplacement
  after update of demande_statut on remplacants
  for each row execute function notifier_demande_remplacement();
