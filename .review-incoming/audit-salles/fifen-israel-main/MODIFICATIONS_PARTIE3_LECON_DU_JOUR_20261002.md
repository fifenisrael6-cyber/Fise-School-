# Partie 3 — Leçon du jour et planning

## Fait
- `student_lesson_progress` et `generated_lessons` sont créées côté serveur avec RLS.
- `daily-lesson` sélectionne la matière du prochain créneau en privilégiant le planning personnel, puis le planning de la salle, avec repli vers la matière la plus en retard.
- Fuseau de décision : `Africa/Douala`.
- Cache partagé : une leçon générée pour un chunk et une langue est réutilisée.
- La génération utilise uniquement le texte du chunk validé et une consigne de niveau scolaire générale.
- La leçon du jour est mise en cache localement, y compris ses 4 questions.
- Écran `DailyLessonPage` accessible depuis l'accueil élève et depuis chaque fil de matière.
- Bouton « Signaler une erreur » relié à une RPC serveur.
- Modes Edge `prepare` et `notify` prévus pour la préparation 24 h avant et la notification 30 min avant.

## Fichiers créés
- `lib/models/smart_learning.dart`
- `lib/core/services/smart_course_service.dart`
- `lib/features/student/pages/daily_lesson_page.dart`
- `supabase/functions/daily-lesson/index.ts`

## Fichiers modifiés
- `supabase/migrations/202610020009_smart_course_offline.sql`
- `lib/core/offline/app_database.dart`
- `lib/core/offline/sync_service.dart`
- `lib/features/student/pages/student_dashboard_page.dart`
- `lib/features/student/pages/subject_channel_page.dart`

## Non testé ici
- exécution réelle des horaires à `Africa/Douala` sur données de production ;
- appel réel à Gemini ;
- émission réelle de push par `send-push` ;
- planificateur Supabase.
