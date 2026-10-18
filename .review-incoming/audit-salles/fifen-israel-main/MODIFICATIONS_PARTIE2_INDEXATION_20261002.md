# Partie 2 — Indexation serveur des PDF

## Fait
- Migration unique `supabase/migrations/202610020009_smart_course_offline.sql` ajoute `course_chunks` et les métadonnées d'indexation sur `course_resources`.
- RLS : lecture des chunks pour élèves/enseignants autorisés de la salle ; aucune écriture directe client.
- Edge Function `supabase/functions/index-course-file/index.ts` : téléchargement privé du PDF, extraction native, transcription Gemini pour les PDF peu textuels, découpage en chunks d'environ 700 mots, aperçu, statut et erreurs.
- Le cache IA n'est servi aux élèves qu'après validation par l'enseignant.
- `TeacherResourcePage` affiche le statut, l'aperçu, le bouton Réindexer et la validation pour l'IA.
- `smart_lesson_enabled` permet d'activer/désactiver le système par cours.

## Fichiers créés
- `supabase/functions/index-course-file/index.ts`

## Fichiers modifiés
- `supabase/migrations/202610020009_smart_course_offline.sql`
- `lib/models/pedagogy.dart`
- `lib/core/services/pedagogy_service.dart`
- `lib/core/services/smart_course_service.dart`
- `lib/features/teacher/pages/teacher_resource_page.dart`
- `lib/features/teacher/pages/create_course_page.dart`

## Non testé ici
- extraction réelle d'un PDF avec le runtime Edge Supabase ;
- transcription réelle d'un PDF scanné avec Gemini ;
- RLS réel avec comptes élève/enseignant/admin ;
- déploiement Edge Function.
