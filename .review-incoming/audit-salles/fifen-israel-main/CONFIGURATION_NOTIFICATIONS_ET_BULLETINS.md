# Fise School — notifications en arrière-plan, notes et bulletins

## 1. Migrations Supabase (dans l'ordre)
- 202610020002_past_papers.sql
- 202610020003_timetable_fixes.sql
- 202610020004_grades_and_bulletins.sql   (notes, bulletins, coefficients)
- 202610020005_device_tokens_push.sql     (jetons des appareils)

## 2. Notes et bulletins : mode d'emploi
- Administrateur > « Notes et bulletins » :
  - onglet Périodes : 6 séquences sont créées ; on peut en ajouter. Activer l'interrupteur PUBLIE les bulletins : les élèves concernés reçoivent une notification.
  - onglet Coef. : choisir une salle, toucher une matière pour changer son coefficient (1 par défaut).
  - onglet Bulletins : choisir une salle puis un élève pour voir (et exporter en PDF) son bulletin, même avant publication.
- Enseignant > « Notes » : salle > matière > période, une note sur 20 par élève, puis « Enregistrer ». L'enseignant doit être affecté à la salle (class_teachers).
- Élève > « Notes et bulletin » : voit uniquement les périodes publiées : notes /20, coefficient, moyenne/min/max de la classe, moyenne générale, rang, appréciation, export PDF.
- Calcul : moyenne générale = somme(note/20 × coefficient) / somme(coefficients) sur les matières notées. Le rang est calculé dans la salle (ex æquo possible).

## 3. Notifications en arrière-plan (Firebase) — à faire une seule fois
Sans cette configuration, l'application fonctionne normalement mais sans push.
1. console.firebase.google.com > Créer un projet > Ajouter une application Android.
   Nom du package : com.example.fise_school (si vous le changez plus tard, refaites cette étape).
2. Télécharger google-services.json. Dans GitHub : Settings > Secrets and variables > Actions > New secret
   Nom : GOOGLE_SERVICES_JSON   Valeur : tout le contenu du fichier.
3. Firebase > Paramètres du projet > Comptes de service > Générer une nouvelle clé privée (fichier JSON).
4. Supabase > Edge Functions > Secrets, ajouter :
   - FIREBASE_SERVICE_ACCOUNT = tout le contenu du fichier JSON de l'étape 3
   - PUSH_WEBHOOK_SECRET = un mot de passe long de votre choix
5. Déployer la fonction send-push (le workflow « Deploy Supabase Edge Functions » le fait au prochain push).
6. Supabase > Database > Webhooks > Create :
   - Table : public.notifications, évènement : Insert
   - Type : Supabase Edge Functions > send-push, méthode POST
   - En-tête HTTP : x-webhook-secret = la même valeur que PUSH_WEBHOOK_SECRET
7. Relancer le build GitHub, installer l'APK, se connecter, accepter l'autorisation de notifications.

Fonctionnement : chaque notification enregistrée (devoir, cours, message, emploi du temps, forum, bulletin, remise de devoir) est envoyée au téléphone, application fermée. Application ouverte, un bandeau s'affiche. À la déconnexion, le téléphone ne reçoit plus les notifications de ce compte.

## 4. Limites connues
- Aucune compilation possible dans l'environnement de travail : les versions firebase_core, firebase_messaging, pdf et printing de pubspec.yaml sont à valider par `flutter pub get` sur GitHub. En cas de conflit de versions, adapter les numéros dans pubspec.yaml.
- Toucher une notification ouvre l'application mais pas l'écran concerné.
- Pas de présences ni de portail parent.
- Bulletin PDF simple (tableau et moyennes) ; pas de logo, ni de signature, ni d'appréciation du conseil de classe.
- iOS : push non configuré (Android seulement).
