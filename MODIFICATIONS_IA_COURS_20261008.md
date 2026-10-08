# Modifications IA + Cours — 08/10/2026

## Fichiers modifiés / ajoutés
- `supabase/functions/gemini-chat/index.ts` : prompts pédagogiques (programme camerounais, structure d'explication, maths/physique/chimie/littéraire), contexte de leçon (`context`), mode admin « brouillon », 2 tentatives si Gemini est surchargé, délai maximum 45 s, gestion des réponses vides/bloquées, erreurs sans détail technique.
- `lib/core/services/gemini_service.dart` : `AiLessonContext`, `AiServiceException`, timeout, messages d'erreur lisibles, `profile` optionnel.
- `lib/features/ai/pages/ai_page.dart` : aides rapides, bouton « Réessayer », contexte de leçon, contrôle de connexion avant appel, réponses avec formules.
- `lib/features/ai/pages/admin_ai_studio_page.dart` (nouveau) : assistant IA admin (brouillon modifiable, aperçu, copie ; aucune publication automatique).
- `lib/features/admin/pages/admin_dashboard_page.dart` : entrée « Assistant IA pédagogique ».
- `lib/core/widgets/rich_lesson_text.dart` (nouveau) : affichage des formules LaTeX (`$...$`, `$$...$$`), titres `##`, gras, listes.
- `lib/features/student/pages/lesson_page.dart` : contenu via `RichLessonText`, carte « Besoin d'aide sur cette leçon ? » (IA avec classe/matière/leçon).
- `lib/features/teacher/pages/create_lesson_page.dart` : encadré d'aide sur la mise en forme (texte seulement).
- `pubspec.yaml` : ajout de `flutter_math_fork`.

## À faire côté Supabase / local
1. `flutter pub get`
2. `supabase functions deploy gemini-chat` (le secret `GEMINI_API_KEY` existant est conservé ; `GEMINI_MODEL` optionnel).
Aucune migration SQL, aucun changement RLS.
