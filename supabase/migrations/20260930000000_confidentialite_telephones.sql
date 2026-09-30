-- Migration : confidentialité des numéros de téléphone (D-024).
-- À exécuter après gel_a_h.sql. Sûre à ré-exécuter.
--
-- ORDRE DE PRODUCTION OBLIGATOIRE : l'app qui ne relit plus
-- pactes.destinataire_telephone doit être déployée ET vérifiée en production
-- AVANT cette migration. Une ancienne version de l'app (qui demande encore
-- cette colonne) verrait toutes ses lectures de Swends refusées.
--
-- Règle : un numéro de téléphone n'est jamais accessible simplement parce
-- qu'on peut lire un Swend. Jusqu'ici, toute personne de confiance ayant accès
-- à un Swend lisait pactes.destinataire_telephone, donc le numéro de l'autre
-- titulaire (côté initiateur) ou celui de son titulaire sans passer par
-- telephone_titulaire_accessible() (côté destinataire).
--
-- Contenu (privilèges colonne uniquement) :
--  1. Plus aucun SELECT de l'app sur pactes.destinataire_telephone.
--  2. Absence de SELECT réaffirmée sur pactes.destinataire_telephone_e164
--     (déjà non lisible en production).
--  3. L'écriture du numéro à la création d'un Swend est conservée (INSERT
--     réaffirmé) : la base continue de rattacher le destinataire par ce numéro.
--
-- Rien d'autre : aucune politique RLS modifiée, aucune fonction créée ni
-- réécrite. Les fonctions serveur (SECURITY DEFINER), la vue interne
-- reservations_a_suivre et le SQL Editor lisent toujours ce numéro.

-- 0. Garde-fou : un SELECT accordé sur toute la table rendrait les retraits
-- par colonne sans effet. Dans ce cas, rien n'est modifié (erreur explicite).
do $$
begin
  if has_table_privilege('authenticated', 'public.pactes', 'select')
     or has_table_privilege('anon', 'public.pactes', 'select') then
    raise exception 'pactes_select_niveau_table : SELECT accordé sur toute la table pactes, retrait par colonne sans effet — migration arrêtée, rien n''a été modifié';
  end if;
end $$;

-- 1 et 2. Lecture retirée (sans effet si déjà absente).
revoke select (destinataire_telephone, destinataire_telephone_e164)
  on public.pactes from public, anon, authenticated;

-- 3. Écriture à la création conservée (déjà accordée : sans effet).
grant insert (destinataire_telephone) on public.pactes to authenticated;

-- Vérification (résultat affiché) ------------------------------------------
select 'Numéro du destinataire non lisible par l''app' as verification,
  (not has_column_privilege('authenticated', 'public.pactes', 'destinataire_telephone', 'select')
   and not has_column_privilege('anon', 'public.pactes', 'destinataire_telephone', 'select'))::text as resultat
union all
select 'Forme canonique du numéro non lisible par l''app',
  (not has_column_privilege('authenticated', 'public.pactes', 'destinataire_telephone_e164', 'select')
   and not has_column_privilege('anon', 'public.pactes', 'destinataire_telephone_e164', 'select'))::text
union all
select 'Aucun SELECT sur toute la table pactes',
  (not has_table_privilege('authenticated', 'public.pactes', 'select')
   and not has_table_privilege('anon', 'public.pactes', 'select'))::text
union all
select 'Création d''un Swend : le numéro s''écrit toujours',
  has_column_privilege('authenticated', 'public.pactes', 'destinataire_telephone', 'insert')::text
union all
select 'Colonnes relues par l''app toujours lisibles',
  (select bool_and(has_column_privilege('authenticated', 'public.pactes', c, 'select'))
   from unnest(array['id', 'type', 'statut', 'dates_proposees', 'date_retenue',
     'nombre_echanges_date', 'restaurant_id', 'initiateur_id', 'initiateur_nom',
     'destinataire_id', 'destinataire_nom', 'created_at']) c)::text
union all
select 'Numéro du titulaire pour sa personne de confiance : fonction inchangée',
  has_function_privilege('authenticated', 'public.telephone_titulaire_accessible(uuid)', 'execute')::text;
