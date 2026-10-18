# Fise School — audit complet et version de référence

Date : 1 octobre 2026

## Périmètre

Audit fichier par fichier de l'archive fournie : code Flutter/Dart, services, modèles, écrans élève/enseignant/admin, migrations Supabase, Edge Functions, stockage, workflows GitHub Actions, permissions Android/iOS et couche hors ligne.

L'archive analysée contenait 82 fichiers Dart et 24 migrations SQL, pour 212 fichiers au total avant nettoyage des artefacts locaux.

## Décisions principales

### 1. Architecture pédagogique

Le modèle retenu est :

Salle → Matière → Programme → Chapitre → Contenu → Activité → Progression élève.

La relation `class_subjects` existait déjà en base mais n'était pas administrable depuis l'interface. La fiche d'une salle possède maintenant un onglet Matières permettant à l'administrateur d'ajouter/retirer les matières compatibles avec le sous-système et le secteur de la salle.

### 2. Enseignant

La création de contenu reste liée à une salle réellement affectée à l'enseignant. La matière est chargée depuis la salle choisie. Les identifiants UUID techniques ne sont plus exposés dans les formulaires de création de devoir/QCM.

### 3. IA

L'ancien système possédait deux écrans IA concurrents et ne gérait que les images.

La version de référence utilise un seul écran IA avec :

- conversation multi-tour dans la session ;
- historique récent envoyé au modèle ;
- photo prise directement avec la caméra ;
- image choisie depuis la galerie ;
- document PDF ;
- fichiers texte/Markdown/CSV ;
- aperçu de la pièce jointe avant envoi ;
- conservation du dernier document/photo comme contexte pour les questions de suivi ;
- limite locale de 8 Mo par pièce jointe ;
- suppression de la conversation ;
- messages d'erreur plus lisibles.

Les fichiers Word/Excel/PowerPoint ne sont pas annoncés comme supportés par l'IA : le moteur Gemini utilisé ici reçoit directement les images, PDF et fichiers texte autorisés. Le système de pièces jointes de messagerie classique reste distinct.

### 4. Sécurité IA

L'ancienne Edge Function acceptait n'importe quel en-tête commençant par `Bearer ` et faisait confiance au profil envoyé par Flutter.

La fonction corrigée :

1. vérifie le vrai jeton Supabase avec `auth.getUser()` ;
2. charge le profil à partir de l'utilisateur authentifié ;
3. ne fait plus confiance au profil scolaire fourni par le client ;
4. vérifie le type et la taille de la pièce jointe ;
5. utilise `gemini-2.5-flash` comme valeur par défaut, cohérente avec la configuration actuelle du projet ;
6. conserve les derniers tours de conversation.

### 5. Mode hors ligne

La couche Drift existait mais `SyncService` et `ConnectivityService` n'étaient pas reliés au cycle réel de l'application.

Le AuthGate synchronise maintenant les cours/leçons de l'élève lorsque la session est disponible et qu'une connexion est présente, et relance une synchronisation lors du retour de la connectivité.

La déconnexion efface également la progression locale afin d'éviter qu'un autre compte sur le même téléphone récupère des données locales du compte précédent.

### 6. Stockage

Une migration supplémentaire durcit la politique d'update des ressources pédagogiques : un enseignant ne peut pas déplacer un objet Storage dans le dossier d'un autre cours.

### 7. Livraison GitHub

Le workflow Android contient déjà `flutter analyze` avant `flutter build apk --release`.

Les artefacts locaux de l'environnement de développement ne doivent pas être poussés : `android/local.properties`, `supabase/.temp`, `.flutter-plugins-dependencies` et les fichiers Flutter générés contenant des chemins locaux ont été exclus de l'archive de livraison.

## Points qui restent volontairement hors de cette correction

- synchronisation bidirectionnelle complète de la progression offline ;
- téléchargement offline de tous les PDF/vidéos/audio ;
- reconnaissance vocale et conversation audio avec l'IA ;
- stockage permanent côté serveur de toutes les conversations IA ;
- extraction automatique des fichiers Word/Excel/PowerPoint pour Gemini.

Ces fonctionnalités demandent des choix supplémentaires de stockage, de coûts et de formats et ne doivent pas être ajoutées de manière improvisée.

## Validation

Le SDK Flutter/Dart n'est pas installé dans l'environnement d'audit. La compilation Flutter n'a donc pas été exécutée localement. Des contrôles structurels ont été effectués : imports relatifs existants, équilibrage syntaxique de base des fichiers modifiés, recherche des anciens champs UUID dans les formulaires enseignant et inspection des migrations/politiques.

La validation de compilation finale doit être faite par GitHub Actions avec Flutter 3.47.5, qui exécute `flutter analyze` puis la construction de l'APK.

## Passage opérationnel du 2 octobre 2026

### Emploi du temps
- Ajout d'un emploi du temps par salle, matière et enseignant.
- L'administrateur peut créer/supprimer les créneaux depuis l'espace administration.
- L'enseignant voit ses propres créneaux.
- L'élève voit l'emploi du temps de sa salle.
- Le serveur bloque les conflits simultanés de classe, enseignant ou salle physique.
- Les changements d'emploi du temps créent une notification.

### Notifications
- Les notifications ne sont plus seulement une table consultée par l'interface : des déclencheurs serveur les créent pour les messages, devoirs publiés, cours publiés, forums et changements d'emploi du temps.
- La page notifications se met à jour en temps réel avec Supabase Realtime.

### Messagerie
- La messagerie privée conserve le périmètre enseignant/élève d'une même classe.
- Le temps réel est activé pour les nouveaux messages.
- Les bulles affichent l'heure et l'état de lecture du message envoyé.
- Les pièces jointes restent stockées dans le bucket privé prévu à cet effet.

### Navigation par rôle
- Élève : accès direct à notifications, messages, cours, QCM, progression et emploi du temps.
- Enseignant : accès direct à cours, QCM, forums, emploi du temps, notifications et messages.
- Administrateur : accès direct à l'emploi du temps depuis le tableau d'administration.

### Nettoyage
- Le libellé d'interface « Données temporaires » n'est plus utilisé et le getter de localisation correspondant a été supprimé.

### Limites restant à traiter pour une V2 complète
- Notifications push Android en arrière-plan : elles nécessitent une intégration FCM/Android et la gestion du jeton appareil.
- Synchronisation bidirectionnelle complète de la progression hors ligne.
- Téléchargement réellement hors ligne des fichiers PDF/vidéo/audio, avec gestion d'espace et de progression.
- Notes/bulletins et présence ne font pas encore partie du modèle fonctionnel actuel de Fise School.
