# Partie 6 — Limites, coûts et sécurité

## Fait
- Quota IA de 10 générations par élève et par jour via `ai_generation_usage`.
- Les leçons déjà générées sont réutilisées avant tout nouvel appel à Gemini.
- Seul le texte du cours et des consignes générales de niveau est envoyé à Gemini ; aucune donnée personnelle de l'élève n'est injectée dans le prompt.
- Gestion explicite des réponses Gemini vides/invalides et des erreurs serveur.
- Clé `GEMINI_API_KEY` uniquement côté Edge Functions.
- La progression et les corrections ne peuvent pas être falsifiées par des INSERT/UPDATE clients directs.
- RLS activée sur toutes les nouvelles tables.
- Secret `SMART_LESSON_CRON_SECRET` prévu pour les modes planifiés.

## Fichiers modifiés
- `supabase/migrations/202610020009_smart_course_offline.sql`
- `supabase/functions/daily-lesson/index.ts`
- `supabase/functions/index-course-file/index.ts`
- `lib/core/services/smart_course_service.dart`
- `.env.example`

## Non testé ici
- quota réel en concurrence ;
- quotas/réponse réels du modèle Gemini ;
- test d'intrusion RLS ;
- configuration réelle des jobs planifiés en production.
