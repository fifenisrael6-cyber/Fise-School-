# Partie 4 — Exercice après la leçon

## Fait
- `generated_exercises` conserve la clé des bonnes réponses côté serveur et n'a pas de politique SELECT client.
- `student_lesson_results` enregistre score, réponses, correction et numéro de tentative.
- RPC `submit_exercise_answers(lesson_id, answers)` corrige côté serveur.
- Une réponse réussie au-dessus du seuil du cours met à jour `student_lesson_progress` et débloque le chunk suivant.
- Seuil par défaut : 50 %, configurable par cours.
- Les réponses hors connexion sont mises en file locale et synchronisées par `sync_service`.
- Le téléphone ne reçoit jamais `answer_key` avant la correction serveur.
- L'écran gère les erreurs de correction sans écran blanc.

## Fichiers créés
- aucune Edge Function supplémentaire ; la génération QCM est intégrée à `daily-lesson`.

## Fichiers modifiés
- `supabase/migrations/202610020009_smart_course_offline.sql`
- `lib/core/offline/app_database.dart`
- `lib/core/offline/sync_service.dart`
- `lib/core/services/smart_course_service.dart`
- `lib/features/student/pages/daily_lesson_page.dart`
- `lib/models/smart_learning.dart`

## Non testé ici
- correction réelle via Supabase RPC ;
- reprise réelle d'une file après mode avion ;
- vérification réelle du verrouillage du chunk suivant.
