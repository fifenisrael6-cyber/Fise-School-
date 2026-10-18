# Fise School — Partie 1 : téléchargement et usage hors ligne

Date : 2026-10-02

## Ce qui est fait
- Drift passe à `schemaVersion 3` avec migration non destructive.
- Table Drift `DownloadedFiles` / SQLite `downloaded_files` : `resource_id`, `course_id`, `user_id`, `file_name`, `mime_type`, `local_path`, `size_bytes`, `remote_updated_at`, `downloaded_at`, `last_opened_at`, `status`.
- Répertoire privé : `getApplicationDocumentsDirectory()/offline/<userId>/<courseId>/`.
- Téléchargement automatique des ressources d'un cours ouvert ou de la matière ouverte.
- Maximum 2 téléchargements simultanés.
- Fichier temporaire `.part`, reprise HTTP Range, 3 tentatives.
- Vidéos de plus de 25 Mo non téléchargées automatiquement ; bouton manuel conservé.
- Limite de stockage 500 Mo par défaut, option Wi-Fi et éviction LRU.
- PDF/image/audio/vidéo ouverts localement lorsqu'ils sont disponibles.
- Détection de remplacement via `course_resources.updated_at`.
- Suppression des copies locales devenues obsolètes ou supprimées côté serveur lors d'une ouverture en ligne.
- Suppression des fichiers au logout.
- Cache local des cours, leçons, devoirs/QCM et file locale des soumissions.
- Synchronisation au retour réseau.
- Reprise automatique des téléchargements en file quand la connexion revient.
- Français/anglais pour les nouveaux écrans.

## Fichiers majeurs créés
- `lib/core/offline/course_offline_service.dart`
- `lib/core/offline/offline_resource_viewer.dart`
- `lib/core/offline/offline_settings.dart`
- `lib/features/settings/pages/offline_storage_page.dart`
- `lib/features/student/widgets/offline_resource_tile.dart`

## Fichiers modifiés
- `pubspec.yaml`
- `lib/core/offline/app_database.dart`
- `lib/core/offline/offline_repository.dart`
- `lib/core/offline/sync_service.dart`
- `lib/core/services/assignment_service.dart`
- `lib/core/services/pedagogy_service.dart`
- `lib/features/auth/widgets/auth_gate.dart`
- `lib/features/settings/pages/settings_page.dart`
- `lib/features/student/pages/subject_channel_page.dart`
- `lib/features/student/pages/course_detail_page.dart`
- `lib/features/student/pages/lesson_page.dart`
- `lib/features/student/pages/assignment_detail_page.dart`

## Migration serveur utilisée par la Partie 1
`supabase/migrations/202610020009_smart_course_offline.sql`

Elle ajoute le champ distant `course_resources.updated_at` nécessaire à la comparaison des versions. Le bucket existant `course-resources` est conservé pour éviter toute rupture du stockage actuel.

## Non testé ici
- Flutter/Dart réel ;
- `build_runner` réel ;
- APK réel ;
- Supabase distant ;
- Storage réel ;
- test mode avion réel ;
- reprise réelle d'un téléchargement interrompu.

Le workflow GitHub a été complété pour exécuter automatiquement `dart run build_runner build --delete-conflicting-outputs` avant `flutter analyze` et la compilation APK.
