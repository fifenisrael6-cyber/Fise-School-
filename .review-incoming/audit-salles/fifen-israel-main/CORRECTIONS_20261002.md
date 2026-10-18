# Fise School — corrections et annales du 2 octobre 2026

## Annales d'examens (nouveau)
- Élève : Accueil → « Annales d'examens » : recherche par matière, filtres examen/année, ouverture du sujet ou du corrigé (PDF/image).
- Administrateur : tableau de bord → « Annales d'examens » : ajout (examen, sous-système, année, session, matière, type sujet/corrigé, fichier), masquer/publier, supprimer.
- Base : migration `202610020002_past_papers.sql` (table `past_papers`, bucket privé `past-papers`, lecture pour tout utilisateur connecté, écriture réservée à l'administrateur).

## Erreurs corrigées
- Parenthèses manquantes : student_main_page, teacher_main_page, teacher_timetable_page, admin_timetable_page, admin_courses_page.
- Emploi du temps enseignant : gestion d'erreur + bouton Réessayer + requête non relancée à chaque affichage.
- Migration `202610020003_timetable_fixes.sql` : l'enseignant voit les créneaux qui lui sont attribués ; plus de notifications en double ; conflits ignorés pour les créneaux inactifs.
- Élève avec salle : plus de mélange avec l'ancien emploi du temps individuel.
- Erreurs silencieuses remplacées par un message (code de paiement) ou un journal (forum, déconnexion).
- Icônes : assets/icon/fise_school.png et fise_school_foreground.png ajoutés (icônes provisoires « FS » à remplacer par le vrai logo) ; le workflow génère les icônes Android.
- Workflow : version Flutter figée retirée (canal stable) ; `flutter analyze --no-fatal-infos`.
- Manifeste : permission POST_NOTIFICATIONS ajoutée.

## À faire
- Appliquer les migrations 202610020002 et 202610020003 dans Supabase.
- Remplacer les icônes provisoires par le logo officiel.
- Changer l'identifiant com.example.fise_school et signer l'APK avec une vraie clé avant le Play Store.
- Les notifications en arrière-plan demandent Firebase (non ajouté).
- Aucun SDK Flutter ici : valider avec GitHub Actions.

## Ajouts (2e passe) : notifications push, notes et bulletins
Voir CONFIGURATION_NOTIFICATIONS_ET_BULLETINS.md.
