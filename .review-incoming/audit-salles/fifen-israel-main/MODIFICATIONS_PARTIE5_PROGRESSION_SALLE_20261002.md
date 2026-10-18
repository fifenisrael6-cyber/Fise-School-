# Partie 5 — Progression comparée

## Fait
- `get_class_progress_summary(class_id)` donne uniquement les statistiques anonymisées de l'élève connecté.
- La comparaison est masquée si la salle compte moins de 5 élèves actifs.
- Aucune liste de noms n'est renvoyée au téléphone d'un élève.
- La courbe hebdomadaire utilise `get_student_weekly_progress`.
- `progress_page.dart` affiche d'abord l'évolution personnelle puis la comparaison anonyme.
- Pour une position basse, le message met l'accent sur la progression et non sur le classement brut.
- Côté enseignant : détail nominatif des élèves, indicateur de retard, moyenne et matières à renforcer.
- Nouveau RPC `get_teacher_class_subject_summary`.

## Fichiers créés
- `lib/features/teacher/pages/teacher_smart_progress_page.dart`

## Fichiers modifiés
- `supabase/migrations/202610020009_smart_course_offline.sql`
- `lib/core/services/smart_course_service.dart`
- `lib/features/student/pages/progress_page.dart`
- `lib/features/teacher/pages/teacher_dashboard_page.dart`
- `lib/models/smart_learning.dart`

## Non testé ici
- calcul réel sur une salle de production ;
- vérification réelle de l'anonymisation RLS avec plusieurs comptes ;
- affichage réel de la courbe sur Android.
