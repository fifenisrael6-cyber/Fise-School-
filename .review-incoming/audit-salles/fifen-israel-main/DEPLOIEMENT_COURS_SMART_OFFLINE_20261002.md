# Déploiement — Cours intelligent + hors ligne

## 1. Supabase
Depuis le projet Flutter :

```bash
supabase db push
```

La seule migration de cette fonctionnalité est :

```text
supabase/migrations/202610020009_smart_course_offline.sql
```

## 2. Secrets Edge
Définir côté Supabase, jamais dans Dart :

```text
GEMINI_API_KEY=<clé Gemini>
GEMINI_MODEL=gemini-2.5-flash
SMART_LESSON_CRON_SECRET=<secret aléatoire long>
```

## 3. Déploiement des fonctions
Les fonctions vérifient déjà leur propre authentification. Pour les modes planifiés, déployer avec le contrôle JWT de plateforme désactivé :

```bash
supabase functions deploy index-course-file --no-verify-jwt
supabase functions deploy daily-lesson --no-verify-jwt
```

## 4. Planification
Créer deux jobs Supabase Cron/Jobs :

### Préparation
- fonction : `daily-lesson`
- fréquence : une fois par jour
- body : `{"mode":"prepare"}`
- header : `x-cron-secret: <SMART_LESSON_CRON_SECRET>`

### Notification
- fonction : `daily-lesson`
- fréquence : toutes les 5 minutes
- body : `{"mode":"notify"}`
- header : `x-cron-secret: <SMART_LESSON_CRON_SECRET>`

La fonction travaille avec le fuseau `Africa/Douala`, déduplique les notifications et vérifie une fenêtre de quelques minutes autour des 30 minutes avant le cours.

## 5. Flutter / Drift
Sur l'environnement qui possède Flutter/Dart :

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter build apk --release
```

## 6. Vérification métier
- ouvrir un cours avec connexion ; attendre qu'une ressource affiche « Disponible hors ligne » ;
- activer le mode avion ; rouvrir le PDF/image/audio/lesson/QCM ;
- remplacer un PDF enseignant ; reconnecter l'élève ; vérifier la nouvelle version ;
- ouvrir « Leçon du jour » ; répondre aux 4 QCM ; vérifier score et déblocage ;
- tester une réponse en mode avion puis la synchronisation ;
- tester une salle de moins de 5 élèves pour vérifier le masquage de la comparaison ;
- tester la vue enseignant avec noms et retard.
