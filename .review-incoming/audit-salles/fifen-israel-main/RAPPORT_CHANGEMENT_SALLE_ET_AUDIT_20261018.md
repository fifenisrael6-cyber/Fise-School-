# Fise School — changement de salle + audit (18 octobre 2026)

## À appliquer sur Supabase (dans l'ordre)
1. `20261018100000_flexible_student_class_change.sql` — nouvelle fonction `list_student_available_classes` et `change_student_class` assouplie.
2. `20261018100100_ensure_assignment_files_bucket.sql` — crée le bucket `assignment-files`.
3. (Une fois) `supabase/REORGANISER_QCM_EXISTANTS.sql` — QCM déjà générés.
4. Redéployer les fonctions `chapter-quiz` et `daily-lesson`.

## Changement de salle
- Toutes les salles actives de la même année / sous-système / enseignement sont proposées, plus seulement le niveau suivant.
- Salle recommandée en haut (niveau suivant, même série), recherche, sections : même niveau, autres salles, niveaux précédents.
- Un clic sur une salle, une confirmation, terminé. Aucun code enseignant.
- Fonctionne aussi pour corriger une erreur faite à l'inscription, ou sans salle active.
- Les onglets Cours et Forum se rechargent après le changement.
- Si la nouvelle fonction SQL n'est pas encore déployée, l'app retombe sur l'ancienne liste.

## Audit (analyse statique, sans compilation)
- Imports : tous les fichiers référencés existent. Parenthèses/accolades équilibrées.
- Tables, fonctions SQL, fonctions Edge utilisées par l'app : toutes présentes, sauf le bucket `assignment-files` (corrigé).
- Écran d'erreur de session : bouton « Réessayer », détail technique masqué.
- Non vérifié : compilation, `flutter analyze`, droits RLS réels, tests sur appareil.
