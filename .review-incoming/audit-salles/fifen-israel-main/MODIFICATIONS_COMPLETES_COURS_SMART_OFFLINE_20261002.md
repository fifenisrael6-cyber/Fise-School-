# Fise School — Parties 1 à 6 terminées

Date : 2026-10-02

## Périmètre
Cette livraison termine l'ensemble du module « Espace cours intelligent + téléchargement hors ligne » sans modifier volontairement les domaines forum, notes, bulletins, paiements, admin catalogue ou messages.

## Partie 1 — Hors ligne
- Téléchargement privé par utilisateur/cours.
- Drift passe à `schemaVersion 3` avec migration non destructive.
- Téléchargements concurrents limités à 2.
- Reprise `.part`, 3 tentatives.
- Vidéo > 25 Mo : téléchargement manuel.
- PDF/images/audio/vidéos lus localement lorsqu'ils sont disponibles.
- Limite de stockage et éviction LRU.
- Nettoyage à la déconnexion, y compris les fichiers physiques privés de l’utilisateur.
- Cache leçons/QCM et file locale de réponses.
- Le workflow Android génère automatiquement le code Drift avec `build_runner` avant l’analyse et la compilation.
- Mise à jour à la connexion via `course_resources.updated_at`.

### Fichiers majeurs
- `lib/core/offline/app_database.dart`
- `lib/core/offline/course_offline_service.dart`
- `lib/core/offline/offline_repository.dart`
- `lib/core/offline/offline_resource_viewer.dart`
- `lib/core/offline/offline_settings.dart`
- `lib/core/offline/sync_service.dart`

## Partie 2 — Indexation PDF
- `course_chunks`.
- Statut pending/indexed/failed.
- Aperçu avant validation.
- `index-course-file`.
- Validation enseignant avant service IA.

## Partie 3 — Leçon du jour
- `student_lesson_progress` et `generated_lessons`.
- `daily-lesson` avec planning personnel puis planning de salle.
- Cache partagé par chunk/langue.
- Préparation 24 h avant et notification 30 min avant via les modes planifiés.
- Écran accessible depuis accueil et matières.

## Partie 4 — Exercice sécurisé
- `generated_exercises` privé.
- Correction via `submit_exercise_answers`.
- Seuil par cours, défaut 50 %.
- File locale hors connexion.
- Correction détaillée après synchronisation.

## Partie 5 — Progression
- Résumé anonyme élève.
- Masquage sous 5 élèves actifs.
- Courbe hebdomadaire.
- Vue enseignant nominative.
- Matières à renforcer.

## Partie 6 — Coûts/sécurité
- Limite 10 générations/jour/élève.
- Cache Gemini.
- Aucun PII élève dans les prompts.
- RLS nouvelles tables.
- Corrections et progression protégées contre écriture directe client.

## Migration unique
`supabase/migrations/202610020009_smart_course_offline.sql`

## Edge Functions
- `supabase/functions/index-course-file/index.ts`
- `supabase/functions/daily-lesson/index.ts`

## Déploiement prévu
1. Appliquer la migration Supabase.
2. Déployer `index-course-file` et `daily-lesson` sans imposer le JWT de plateforme, car ces fonctions vérifient elles-mêmes le JWT utilisateur et leur mode planifié.
3. Définir les secrets Edge `GEMINI_API_KEY`, `GEMINI_MODEL` (facultatif) et `SMART_LESSON_CRON_SECRET`.
4. Configurer deux jobs planifiés : `daily-lesson` en mode `prepare` une fois par jour et `daily-lesson` en mode `notify` toutes les 5 minutes, avec le secret de planification.

## Tests non réalisables dans cet environnement
- `flutter analyze` : Flutter/Dart non installé dans cet environnement.
- `dart run build_runner build --delete-conflicting-outputs` : Dart non installé.
- Compilation APK : non exécutée.
- `supabase db push` : non exécuté.
- Déploiement réel des Edge Functions : non exécuté.
- Tests RLS avec comptes réels : non exécutés.
- Test mode avion/reprise réel : non exécuté.
- Test PDF et Gemini réel : non exécuté.

## Point Drift honnête
`app_database.g.dart` existant n'a pas pu être régénéré ici car Dart/Build Runner n'est pas disponible. Les nouvelles tables hors ligne ajoutées pour cette fonctionnalité sont créées par SQL Drift custom dans `AppDatabase` lors de la migration de schéma. Au prochain environnement Flutter, exécuter `dart run build_runner build --delete-conflicting-outputs` avant l'analyse finale.
