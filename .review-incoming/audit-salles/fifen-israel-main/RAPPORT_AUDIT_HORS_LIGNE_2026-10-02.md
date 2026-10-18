# Fise School — audit, test « en tant qu'utilisateur » et mode hors ligne (2 octobre 2026)

## 0. Ce qui a été fait, ce qui n'a pas pu l'être

**Important — limite de cette vérification.** Aucun SDK Flutter/Dart ni accès réseau n'était disponible : le code n'a été ni compilé, ni exécuté, ni testé sur téléphone. Les « tests utilisateur » ci-dessous sont des **parcours simulés en lisant le code** (écran → service → requête → repli). Ils trouvent de vrais bogues, mais ne remplacent pas un essai sur Android. La validation finale reste : `flutter pub get`, `flutter analyze`, puis un essai en mode avion.

Contrôles effectués ici : équilibre des parenthèses/accolades sur 100 fichiers Dart, existence de tous les imports, imports inutilisés, variables `catch` inutilisées (avertissements qui font échouer `flutter analyze` dans votre workflow).

## 1. Bogues trouvés en jouant l'élève (et corrigés)

| # | Parcours | Avant | Après |
|---|---|---|---|
| 1 | Ouvrir l'app sans réseau (session déjà connectée) | Écran d'erreur : le profil était relu sur le serveur, rien en local | Dernier profil connu repris du cache (jamais celui d'un autre compte) |
| 2 | Ouvrir une leçon sans réseau | Erreur : la progression et la liste des documents étaient demandées au serveur | La leçon s'ouvre ; la progression est lue/écrite en local |
| 3 | « Terminer la leçon » sans réseau | « Impossible de terminer la leçon » | Enregistrée localement, envoyée automatiquement au retour du réseau (une leçon terminée n'est jamais rétrogradée) |
| 4 | Écran Progression sans réseau | Erreur totale (requêtes directes) | Calculé depuis les copies locales + progression non envoyée |
| 5 | Matières de la salle, emploi du temps, notifications, annales, bulletins publiés, devoirs/QCM (lecture), forum (lecture) | Erreur dès qu'il n'y a plus de réseau | Dernière copie locale affichée |
| 6 | Synchronisation | Une seule fois par connexion, et marquée « faite » même si hors ligne → jamais relancée | Relancée à chaque retour du réseau ; envoi de la progression en attente d'abord |
| 7 | Cours supprimés/dépubliés par l'enseignant | Restaient visibles hors ligne | La liste locale est remplacée par la liste serveur |
| 8 | **Déconnexion depuis Paramètres** | Appelait directement Supabase : le cache local (cours, notes, bulletins) restait sur le téléphone pour le compte suivant | Tous les chemins de déconnexion passent par le même nettoyage |
| 9 | Connexion lente (2G/3G) | Requête pouvant rester bloquée longtemps | Délai de 12 s puis bascule sur le cache |
| 10 | Base locale | Plusieurs connexions SQLite ouvertes sur le même fichier | Une seule connexion partagée |
| 11 | Build GitHub | Un import inutilisé (`teacher_main_page.dart`) et 17 variables `catch` inutilisées → avertissements bloquants | Corrigés |

Nouveau : barre orange « Mode hors ligne » en haut de l'écran (affiche le nombre d'éléments en attente d'envoi). Elle n'altère pas la navigation.

## 2. Ce qui nécessite toujours le réseau (volontairement)

- Ouvrir un PDF, une vidéo ou une annale (liens signés temporaires) — le téléchargement hors ligne des fichiers n'est pas fait.
- Répondre à un QCM / remettre un devoir, envoyer un message ou un message de forum, l'IA, le paiement Premium, marquer une notification comme lue.
- Espaces enseignant (création) et administrateur.

Ces actions échouent avec un message, sans planter. Les mettre en file d'attente (comme la progression) est faisable mais demande des règles de conflit (devoir déjà clos, doublons de messages) à décider avec vous.

## 3. Comparaison avec les applications scolaires camerounaises

Sources vérifiées aujourd'hui (descriptions publiques) : Skolarr, ConcourGuide-CMR, MonProf, E-School-Connected, VersityLife (universitaire). OnBuch et Scolive : je n'ai pas retrouvé leurs pages en ligne ; je reprends la comparaison de votre audit du 2 octobre, **non revérifiée**.

| Fonction | Fise School | Concurrents |
|---|---|---|
| Cours par salle / matière / programme (FR + EN) | Oui, relié à la structure réelle des salles | Skolarr : 250+ cours en ligne, catalogue général |
| QCM / exercices | Oui | Skolarr, ConcourGuide : quiz |
| Annales | Oui (admin les publie) | ConcourGuide : annales de concours |
| IA (photo, PDF) | Oui | Skolarr, ConcourGuide : assistant IA |
| Emploi du temps avec détection de conflits | Oui | VersityLife : emploi du temps (université) |
| Notes, bulletins, rang, PDF | Oui (nouveau) | VersityLife : notes (université) |
| Messagerie élève ↔ enseignant | Oui | MonProf : messagerie |
| Notifications | Oui (push à configurer via Firebase) | ConcourGuide, E-School-Connected |
| Mode hors ligne | Cours/leçons + consultation (désormais) | VersityLife annonce le hors ligne |
| Paiement Mobile Money | Premium seulement | VersityLife : frais de scolarité par MTN/Orange |
| **Portail parent** | **Non** | MonProf, E-School-Connected |
| **Présences / absences** | **Non** | Fonction courante des outils de gestion scolaire |
| Frais de scolarité | Non | VersityLife |
| Communauté / compétition entre élèves | Forum par salle | ConcourGuide |

Forces : sécurité par salle (droits côté serveur), séparation francophone/anglophone, bulletins et emploi du temps liés aux affectations. Écarts réels : portail parent, présences, frais de scolarité, téléchargement des fichiers hors ligne.

## 4. Reste à faire (je ne l'ai pas improvisé)

1. **Valider le build** : `flutter pub get` (versions `firebase_*`, `pdf`, `printing`, et `sdk: ^3.13.0` non vérifiées), `flutter analyze`, essai en mode avion.
2. Remplacer l'identifiant `com.example.fise_school` et signer l'APK avec une vraie clé (aujourd'hui clé de debug) — à faire avant le Play Store ; si l'identifiant change, refaire l'étape Firebase.
3. Remplacer les icônes provisoires « FS » par le vrai logo.
4. Firebase / `send-push` : suivre `CONFIGURATION_NOTIFICATIONS_ET_BULLETINS.md`.
5. Toucher une notification doit ouvrir l'écran concerné (ouvre seulement l'app).
6. Présences et portail parent : nouvelles migrations + droits (RLS) + écrans ; à lancer comme chantier séparé, car des données de présence d'élèves mineurs demandent des règles d'accès précises.
7. Téléchargement hors ligne des PDF/audio (gestion de l'espace, progression, suppression).
8. Les leçons retirées par l'enseignant restent dans le cache jusqu'à la déconnexion (seuls les cours sont purgés).

## 5. Fichiers modifiés / ajoutés

Ajoutés : `lib/core/offline/json_cache.dart`, `pending_progress.dart`, `local_cleanup.dart`, `offline_banner.dart`.
Modifiés : `session_service.dart`, `auth_service.dart`, `auth_gate.dart`, `app.dart`, `settings_page.dart`, `lesson_page.dart`, `progress_page.dart`, `teacher_main_page.dart`, `offline_repository.dart`, `sync_service.dart`, et les services `pedagogy`, `timetable`, `notification`, `past_paper`, `grade`, `assignment`, `forum`, `exam_catalog`.
Aucune migration SQL, aucun changement du schéma Drift (pas de régénération `build_runner`).
